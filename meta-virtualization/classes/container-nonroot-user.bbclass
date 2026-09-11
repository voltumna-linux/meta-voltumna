# For secure and production environments, we want to run containers as a
# non-root user. Some applications, such as Python, require a $HOME
# directory with proper permissions. Because OCI_LAYERS :directories:
# copies with 'cp -a --no-preserve=ownership', we need a fixup function
# to create the proper permissions and ownership in a new raw layer.

# The behavior here is inspired by dhi.io/python:3 (Docker Hardened Image)

# IMPORTANT: this class MUST be inherited AFTER image-oci. Its
# oci_nonroot_inject_user() function is registered as a do_image_oci
# prefunc via '+=', and image-oci's oci_multilayer_install_packages()
# (which populates OCI_LAYER_*_ROOTFS) is also a do_image_oci prefunc.
# BitBake runs prefuncs in the order they were appended to the varflag,
# so the file that inherits second gets its prefunc called second.
# If container-nonroot-user is inherited before image-oci, the
# per-layer rootfs vars are not yet set when the injection runs, no
# layer ships /etc/passwd, and the nonroot account silently doesn't
# make it into the image. The anonymous python block below asserts
# that image-oci has already been inherited to catch that ordering
# mistake at parse time.
python () {
    if 'image-oci' not in (d.getVar('__inherit_cache') or []):
        # __inherit_cache is not part of the public API; fall back to
        # checking for a variable that image-oci sets, so this survives
        # a bitbake internals rename.
        if not d.getVar('OCI_IMAGE_TAG'):
            bb.fatal("container-nonroot-user must be inherited after "
                     "image-oci — the per-layer rootfs vars its "
                     "prefunc consumes are populated by image-oci's "
                     "own prefunc, and prefunc order follows "
                     "inherit order.")
}

inherit extrausers

# NONROOT_USER must be a bare identifier (no quotes or backslash, etc.)
NONROOT_USER ?= "nonroot"
NONROOT_UID ?= "65532"
NONROOT_GID ?= "65532"
# Space-separated absolute paths to create in the image, owned by nonroot.
NONROOT_OWNED_DIRS ?= ""

# ---------------------------------------------------------------------------
# Create the unprivileged "nonroot" user (uid 65532, group 65532)
# ---------------------------------------------------------------------------
EXTRA_USERS_PARAMS += "\
    groupadd -g ${NONROOT_GID} ${NONROOT_USER}; \
    useradd -m -u ${NONROOT_UID} -g ${NONROOT_GID} \
            -d /home/${NONROOT_USER}  ${NONROOT_USER}; \
"

# Allow a container to choose to run as 'root'
OCI_IMAGE_RUNTIME_UID ?= "${NONROOT_UID}"
OCI_IMAGE_ENV_VARS = "HOME=/home/${NONROOT_USER}"

# In multi-layer OCI mode the image is assembled from per-layer package
# installs (oci_multilayer_install_packages in image-oci-umoci.inc), not from
# IMAGE_ROOTFS. extrausers/EXTRA_USERS_PARAMS only edits IMAGE_ROOTFS, so the
# nonroot account never reaches the image. Inject it into the layer rootfs that
# ships /etc/passwd, before IMAGE_CMD:oci assembles the layers.
python oci_nonroot_inject_user() {
    import os

    if (d.getVar('OCI_LAYER_MODE') or 'single') != 'multi':
        return  # single-layer mode builds from IMAGE_ROOTFS; extrausers handles it

    user = d.getVar('NONROOT_USER')
    uid  = d.getVar('NONROOT_UID')
    gid  = d.getVar('NONROOT_GID')
    home = '/home/%s' % user

    # shell field is cosmetic (runtime user is pinned numerically via
    # OCI config.user); /bin/sh matches dhi.io passwd entries.
    passwd_line = '%s:x:%s:%s:%s:%s:/bin/sh\n' % (user, uid, gid, user, home)
    group_line  = '%s:x:%s:\n' % (user, gid)
    shadow_line = '%s:!:::::::\n' % user

    def append_once(path, line, key):
        if not os.path.exists(path):
            return False
        with open(path) as f:
            if any(l.startswith(key) for l in f):
                return True            # already present (idempotent rebuild)
        with open(path, 'a') as f:
            f.write(line)
        return True

    key = user + ':'
    count = int(d.getVar('OCI_LAYER_COUNT') or 0)
    found = False
    for i in range(1, count + 1):
        rootfs = d.getVar('OCI_LAYER_%d_ROOTFS' % i)
        if not rootfs:
            continue
        # add to every layer that carries /etc/passwd so the topmost wins too
        if append_once(os.path.join(rootfs, 'etc/passwd'), passwd_line, key):
            append_once(os.path.join(rootfs, 'etc/group'),  group_line,  key)
            append_once(os.path.join(rootfs, 'etc/shadow'), shadow_line, key)  # optional
            found = True

    if not found:
        bb.warn("container-nonroot-user: no layer ships /etc/passwd; '%s' not "
                "added — is base-passwd in a packages: layer?" % user)
}

# Must run AFTER oci_multilayer_install_packages populates OCI_LAYER_*_ROOTFS.
do_image_oci[prefuncs] += "oci_nonroot_inject_user"

# Make sure we can write to e.g. /home/nonroot/.python_history
# using :directories: in OCI_LAYERS does not preserve permissions.
fakeroot fix_oci_home_perms() {
    cd ${IMGDEPLOYDIR}
    image_name="${IMAGE_NAME}${IMAGE_NAME_SUFFIX}-oci"
    layer_tar="${WORKDIR}/oci-home-fix-layer.tar"

    rm -f "$layer_tar"

    # BitBake expands ${NONROOT_USER} etc. at parse time *before*
    # shell sees the body, so single quoted 'PYEOF' is okay.
    python3 - "$layer_tar" <<'PYEOF'
import sys, tarfile, time

layer_tar = sys.argv[1]
mtime = int(time.time())

uid = ${NONROOT_UID}
gid = ${NONROOT_GID}

# (path, mode, uid, gid)  -- paths are tar-relative, no leading slash
entries = [
    ("home",         0o755, 0,     0),
    ("home/${NONROOT_USER}", 0o700, uid, gid),
]

seen = {entry[0] for entry in entries}
for nonrootdir in "${NONROOT_OWNED_DIRS}".split():
    parts = nonrootdir.strip("/").split("/")
    for i, _ in enumerate(parts):
        path = "/".join(parts[:i+1])
        if path in seen:
            continue
        seen.add(path)
        leaf = (i == len(parts) - 1)
        # leaf -> nonroot-owned; parents -> root:root, just to scaffold the path
        entries.append((path, 0o755, uid if leaf else 0, gid if leaf else 0))

with tarfile.open(layer_tar, "w") as tar:
    for name, mode, uid, gid in entries:
        info = tarfile.TarInfo(name=name)
        info.type  = tarfile.DIRTYPE
        info.mode  = mode
        info.uid   = uid
        info.gid   = gid
        info.uname = ""   # numeric-only; let umoci canonicalize
        info.gname = ""
        info.mtime = mtime
        tar.addfile(info)
PYEOF

    umoci raw add-layer --image "$image_name:${OCI_IMAGE_TAG}" "$layer_tar"
    rm -f "$layer_tar"

    # Adding the raw layer mutates the OCI image directory, so the tar outputs
    # produced by do_image_oci are now stale and must be rebuilt. The image
    # *directory* ($image_name) is the source of truth; the .tar files are
    # derived from it and only exist when OCI_IMAGE_TAR_OUTPUT is set, so mirror
    # that gating (see image-oci-umoci.inc) instead of rebuilding unconditionally.
    # Guard the assumption: an OCI layout always has an index.json, so its
    # absence means the packaging layout in image-oci.bbclass has changed (or
    # the dir is empty). Fail loudly rather than emit a silently-broken tarball.
    if [ -n "${OCI_IMAGE_TAR_OUTPUT}" ]; then
        if [ ! -f "$image_name/index.json" ]; then
            bbfatal "fix_oci_home_perms: '$image_name' is not an OCI image layout (no index.json) in ${IMGDEPLOYDIR}; image-oci packaging layout may have changed"
        fi
        rm -f "$image_name.tar" "$image_name-dir.tar"
        ( cd "$image_name" && tar -cf "../$image_name.tar" "." )
        tar -cf "$image_name-dir.tar" "$image_name"
    fi
}
do_image_oci[postfuncs] += "fix_oci_home_perms"
