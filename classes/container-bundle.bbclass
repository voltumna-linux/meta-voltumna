# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# container-bundle.bbclass
# ===========================================================================
# Container bundling class for creating installable container packages
# ===========================================================================
#
# This class creates packages that bundle pre-processed container images.
# When these packages are installed via IMAGE_INSTALL, the containers are
# automatically merged into the target image's container storage.
#
# ===========================================================================
# Component Relationships
# ===========================================================================
#
# To bundle a local container like "myapp:autostart", three recipe types
# work together:
#
#   1. Application Recipe (builds the software)
#      recipes-demo/myapp/myapp_1.0.bb
#      ├── Compiles application binaries
#      └── Creates installable package (myapp)
#
#   2. Container Image Recipe (creates OCI image containing the app)
#      recipes-demo/images/myapp-container.bb
#      ├── inherit image image-oci
#      ├── IMAGE_INSTALL = "myapp"
#      └── Produces: ${DEPLOY_DIR_IMAGE}/myapp-container-latest-oci/
#
#   3. Bundle Recipe (packages container images for deployment)
#      recipes-demo/bundles/my-bundle_1.0.bb
#      ├── inherit container-bundle
#      ├── CONTAINER_BUNDLES = "myapp-container:autostart"
#      └── Creates installable package with OCI data
#
# Flow diagram:
#
#   myapp_1.0.bb                    myapp-container.bb
#   (application)                   (container image)
#        │                               │
#        │ IMAGE_INSTALL="myapp"         │ inherit image-oci
#        └──────────────┬────────────────┘
#                       │
#                       ▼
#              myapp-container-latest-oci/
#              (OCI directory in DEPLOY_DIR_IMAGE)
#                       │
#                       │ CONTAINER_BUNDLES="myapp-container"
#                       ▼
#              my-bundle_1.0.bb ──────► my-bundle package
#              (inherits container-bundle)    │
#                                             │ IMAGE_INSTALL="my-bundle"
#                                             ▼
#                                    container-image-host
#                                    (target host image)
#
# ===========================================================================
# When to Use This Class vs BUNDLED_CONTAINERS
# ===========================================================================
#
# There are two ways to bundle containers into a host image:
#
#   1. BUNDLED_CONTAINERS variable (simpler, no extra recipe needed)
#      Set in local.conf or image recipe:
#        BUNDLED_CONTAINERS = "container-base:docker myapp-container:docker:autostart"
#
#   2. container-bundle packages (this class)
#      Create a bundle recipe, install via IMAGE_INSTALL
#
# Decision guide:
#
#   Use Case                                    | BUNDLED_CONTAINERS | Bundle Recipe
#   --------------------------------------------|--------------------|--------------
#   Simple: containers in one host image        | recommended        | overkill
#   Reuse containers across multiple images     | repetitive         | recommended
#   Remote containers (docker.io/library/...)   | not supported      | required
#   Package versioning and dependencies         | not supported      | supported
#   Distribute pre-built container set          | not supported      | supported
#
# For most single-image use cases, BUNDLED_CONTAINERS is simpler:
#   - No bundle recipe needed
#   - Dependencies auto-generated at parse time
#   - vrunner batch-import runs once for all containers
#
# Use this class (container-bundle) when you need:
#   - Remote container fetching via skopeo
#   - A distributable/versioned package of containers
#   - To share the same bundle across multiple different host images
#
# ===========================================================================
# Usage
# ===========================================================================
#
#   inherit container-bundle
#
#   CONTAINER_BUNDLES = "\
#       myapp-container \
#       mydb-container:autostart \
#       docker.io/library/redis:7 \
#   "
#
#   # REQUIRED for remote containers (sanitize key: replace / and : with _):
#   CONTAINER_DIGESTS[docker.io_library_redis_7] = "sha256:..."
#
#   # To get the digest, use skopeo:
#   #   skopeo inspect docker://docker.io/library/redis:7 | jq -r '.Digest'
#
# Variable format: source[:autostart-policy]
#   - source: Either a container image recipe name or a remote registry URL
#     * Local: "myapp-container", "container-base" (recipe names)
#     * Remote: "docker.io/library/alpine:3.19" (contains / or .)
#   - autostart-policy: Optional. autostart | always | unless-stopped | on-failure
#
# Runtime Selection (in order of precedence):
#   1. CONTAINER_BUNDLE_RUNTIME in recipe (explicit override)
#   2. CONTAINER_PROFILE distro/local.conf setting
#   3. Default: "docker"
#
# Remote containers:
#   - Must have pinned digest via CONTAINER_DIGESTS
#   - A licensing warning is emitted during fetch
#   - Fetched using skopeo-native in do_fetch phase
#
# Local containers:
#   - Must be container IMAGE recipes (inherit image-oci)
#   - Built via dependency on recipe:do_image_complete
#   - OCI directory picked up from DEPLOY_DIR_IMAGE
#
# ===========================================================================
# Integration with container-cross-install.bbclass
# ===========================================================================
#
# This class creates packages that are processed by container-cross-install:
#   1. Installs OCI directories to ${datadir}/container-bundles/${RUNTIME}/oci/
#   2. Installs refs file to ${datadir}/container-bundles/${RUNTIME}/${PN}.refs
#   3. Installs metadata to ${datadir}/container-bundles/${PN}.meta
#   4. container-cross-install.bbclass imports these via vrunner at image time
#
# The runtime subdirectory (docker/ vs podman/) tells container-cross-install
# which vrunner runtime to use for import.
#
# ===========================================================================
# Custom Service Files (CONTAINER_SERVICE_FILE)
# ===========================================================================
#
# For containers requiring specific startup configuration, provide custom
# service files instead of auto-generated ones:
#
#   SRC_URI = "file://myapp.service file://mydb.container"
#
#   CONTAINER_BUNDLES = "\
#       myapp-container:autostart \
#       mydb-container:autostart \
#   "
#
#   CONTAINER_SERVICE_FILE[myapp-container] = "${UNPACKDIR}/myapp.service"
#   CONTAINER_SERVICE_FILE[mydb-container] = "${UNPACKDIR}/mydb.container"
#
# Custom files are installed to ${datadir}/container-bundles/${RUNTIME}/services/
# and used by container-cross-install instead of generating default services.
#
# For Docker, provide a .service file; for Podman, provide a .container Quadlet.
#
# See docs/container-bundling.md for detailed examples.
#
# See also: container-cross-install.bbclass

CONTAINER_BUNDLES ?= ""

# Default runtime based on CONTAINER_PROFILE
# Can be overridden in recipe with CONTAINER_BUNDLE_RUNTIME = "podman"
def get_bundle_runtime(d):
    """Determine container runtime from CONTAINER_PROFILE or default to docker"""
    profile = d.getVar('CONTAINER_PROFILE') or 'docker'
    if profile in ['podman']:
        return 'podman'
    # docker, containerd, k3s-*, default all use docker storage format
    return 'docker'

CONTAINER_BUNDLE_RUNTIME ?= "${@get_bundle_runtime(d)}"

# Inherit shared functions for multiconfig/machine/arch mapping
inherit container-common

# Inherit deploy for optional OCI base layer deployment (see CONTAINER_BUNDLE_DEPLOY)
inherit deploy

# Dependencies on native tools
# vcontainer-native provides vrunner.sh
# Blobs come from multiconfig builds (vdkr-initramfs-create, vpdmn-initramfs-create)
DEPENDS += "qemuwrapper-cross qemu-system-native skopeo-native"
DEPENDS += "vcontainer-native"

VRUNTIME_MULTICONFIG = "${@get_vruntime_multiconfig(d)}"
VRUNTIME_MACHINE = "${@get_vruntime_machine(d)}"
BLOB_ARCH = "${@get_blob_arch(d)}"

# Path to vrunner.sh from vcontainer-native
VRUNNER_PATH = "${STAGING_BINDIR_NATIVE}/vrunner.sh"

# Blobs come from multiconfig deploy directory
# These are built by vdkr-initramfs-create and vpdmn-initramfs-create
VDKR_BLOB_DIR = "${TOPDIR}/tmp-${VRUNTIME_MULTICONFIG}/deploy/images/${VRUNTIME_MACHINE}/vdkr"
VPDMN_BLOB_DIR = "${TOPDIR}/tmp-${VRUNTIME_MULTICONFIG}/deploy/images/${VRUNTIME_MACHINE}/vpdmn"

def is_remote_container(source):
    """Detect if source is a registry URL vs local recipe name.

    Remote indicators: contains '/' or '.' in the base name (before first :)
    Local: simple recipe name like "myapp" or "container-base"
    """
    base = source.split(':')[0] if ':' in source else source
    return '/' in base or '.' in base

python __anonymous() {
    # Conditionally set mcdepends when vruntime multiconfig is configured
    # (avoids parse errors when BBMULTICONFIG is not set, e.g. yocto-check-layer)
    vruntime_mc = d.getVar('VRUNTIME_MULTICONFIG')
    bbmulticonfig = (d.getVar('BBMULTICONFIG') or "").split()
    if vruntime_mc and vruntime_mc in bbmulticonfig:
        d.setVarFlag('do_compile', 'mcdepends',
            'mc::%s:vdkr-initramfs-create:do_deploy mc::%s:vpdmn-initramfs-create:do_deploy' % (vruntime_mc, vruntime_mc))

    bundles = (d.getVar('CONTAINER_BUNDLES') or "").split()
    if not bundles:
        return

    # Get runtime from CONTAINER_BUNDLE_RUNTIME (set based on CONTAINER_PROFILE)
    runtime = d.getVar('CONTAINER_BUNDLE_RUNTIME') or 'docker'
    if runtime not in ['docker', 'podman']:
        bb.fatal(f"Invalid CONTAINER_BUNDLE_RUNTIME '{runtime}': must be 'docker' or 'podman'")

    local_recipes = []
    remote_urls = []
    processed_bundles = []

    for bundle in bundles:
        # New format: source[:autostart-policy]
        # For remote URLs like docker.io/library/redis:7, we need to handle
        # the tag colon differently from the autostart colon
        if is_remote_container(bundle):
            # Remote: could be "docker.io/library/redis:7" or "docker.io/library/redis:7:autostart"
            # Find the last colon that's an autostart policy
            if bundle.endswith(':autostart') or bundle.endswith(':always') or \
               bundle.endswith(':unless-stopped') or bundle.endswith(':on-failure') or \
               bundle.endswith(':no'):
                last_colon = bundle.rfind(':')
                source = bundle[:last_colon]
                autostart = bundle[last_colon+1:]
            else:
                source = bundle
                autostart = ""
            remote_urls.append(source)
        else:
            # Local: "myapp" or "myapp:autostart"
            parts = bundle.split(':')
            source = parts[0]
            autostart = parts[1] if len(parts) > 1 else ""
            local_recipes.append(source)

        # Store normalized format: source:runtime:autostart (for metadata file)
        processed_bundles.append(f"{source}:{runtime}:{autostart}" if autostart else f"{source}:{runtime}")

    # Add dependencies for local container recipes
    # Local containers are built in the MAIN context (not multiconfig)
    # and their OCI images are in main DEPLOY_DIR_IMAGE
    if local_recipes:
        deps = ""
        for recipe in local_recipes:
            # Container recipes produce OCI images via do_image_complete
            deps += f" {recipe}:do_image_complete"
        if deps:
            d.appendVarFlag('do_compile', 'depends', deps)

    # Store parsed lists for tasks
    d.setVar('_LOCAL_CONTAINERS', ' '.join(local_recipes))
    d.setVar('_REMOTE_CONTAINERS', ' '.join(remote_urls))
    d.setVar('_PROCESSED_BUNDLES', ' '.join(processed_bundles))
    d.setVar('_BUNDLE_RUNTIME', runtime)

    # Remote containers are fetched during do_fetch (network is allowed there).
    # extend_recipe_sysroot populates the native sysroot so skopeo is available.
    # Explicit do_fetch depends ensures skopeo-native is built before our
    # do_fetch runs (DEPENDS alone only gates do_prepare_recipe_sysroot).
    if remote_urls:
        d.appendVarFlag('do_fetch', 'depends', ' skopeo-native:do_populate_sysroot')
        d.appendVarFlag('do_fetch', 'prefuncs', ' extend_recipe_sysroot')
        d.appendVarFlag('do_fetch', 'postfuncs', ' do_fetch_containers')

    # Build service file map for custom service files
    # Format: container1=/path/to/file1;container2=/path/to/file2
    service_mappings = []
    for bundle in bundles:
        # Extract container name (handle both local and remote formats)
        if is_remote_container(bundle):
            if bundle.endswith(':autostart') or bundle.endswith(':always') or \
               bundle.endswith(':unless-stopped') or bundle.endswith(':on-failure') or \
               bundle.endswith(':no'):
                last_colon = bundle.rfind(':')
                source = bundle[:last_colon]
            else:
                source = bundle
        else:
            parts = bundle.split(':')
            source = parts[0]

        custom_file = d.getVarFlag('CONTAINER_SERVICE_FILE', source)
        if custom_file:
            service_mappings.append(f"{source}={custom_file}")

    d.setVar('_CONTAINER_SERVICE_FILE_MAP', ';'.join(service_mappings))
}

# S must be a real directory
S = "${WORKDIR}/sources"
B = "${WORKDIR}/build"

do_unpack[noexec] = "1"
do_patch[noexec] = "1"
do_configure[noexec] = "1"

python do_fetch_containers() {
    import subprocess
    import os

    remote_containers = (d.getVar('_REMOTE_CONTAINERS') or "").split()
    if not remote_containers:
        return

    workdir = d.getVar('WORKDIR')
    fetched_dir = os.path.join(workdir, 'fetched')
    os.makedirs(fetched_dir, exist_ok=True)

    # Find skopeo in native sysroot (populated by extend_recipe_sysroot prefunc)
    # skopeo-native installs to sbindir, not bindir
    staging_sbindir = d.getVar('STAGING_SBINDIR_NATIVE')
    skopeo = os.path.join(staging_sbindir, 'skopeo')

    for url in remote_containers:
        if not url:
            continue

        # Digest is REQUIRED for remote containers
        # Varflag key must be sanitized (no / or : allowed in BitBake varflag names)
        sanitized_key = url.replace('/', '_').replace(':', '_')
        digest = d.getVarFlag('CONTAINER_DIGESTS', sanitized_key)
        if not digest:
            bb.fatal(f"Remote container '{url}' requires a pinned digest.\n"
                     f"Add: CONTAINER_DIGESTS[{sanitized_key}] = \"sha256:...\"\n"
                     f"Get digest with: skopeo inspect docker://{url} | jq -r '.Digest'")

        # Emit licensing warning
        bb.warn(f"Fetching third-party container: {url}\n"
                f"Ensure you have rights to redistribute this container in your image.\n"
                f"Check the container's license terms before distribution.")

        # Strip tag from URL when using digest (skopeo doesn't support both)
        # e.g., docker.io/library/busybox:1.36 -> docker.io/library/busybox
        base_url = url.rsplit(':', 1)[0] if ':' in url.split('/')[-1] else url
        src = f"{base_url}@{digest}"
        name = url.replace('/', '_').replace(':', '_')
        dest_dir = os.path.join(fetched_dir, name)
        dest = f"oci:{dest_dir}:latest"

        bb.note(f"Fetching {src} -> {dest}")

        try:
            subprocess.check_call([skopeo, 'copy', f'docker://{src}', dest])
        except subprocess.CalledProcessError as e:
            bb.fatal(f"Failed to fetch container '{url}': {e}")
}

# do_fetch_containers runs as a postfunc of do_fetch (set in __anonymous
# when remote containers are configured). This keeps network access within
# do_fetch where it is permitted by yocto-check-layer.

do_compile() {
    set -e

    mkdir -p "${S}"

    # Clean OCI directory to avoid nested copies from incremental builds
    rm -rf "${B}/oci"
    mkdir -p "${B}/oci"

    # Clear refs file to avoid duplicates from incremental builds
    : > "${B}/oci-refs.txt"

    RUNTIME="${_BUNDLE_RUNTIME}"
    bbnote "Collecting OCI images for runtime: ${RUNTIME}"

    # Collect OCI directories - NO vrunner here, just copy OCI images
    # vrunner will be run ONCE by container-cross-install at rootfs time
    for bundle in ${_PROCESSED_BUNDLES}; do
        # Extract source from bundle format
        source=$(echo "$bundle" | sed -E 's/:(docker|podman)(:(autostart|always|unless-stopped|on-failure|no))?$//')
        collect_oci "$source"
    done

    # Store metadata for autostart processing (one bundle per line)
    printf '%s\n' ${_PROCESSED_BUNDLES} > "${B}/bundle-metadata.txt"
}

collect_oci() {
    local source="$1"

    # Determine OCI directory and image reference
    if echo "$source" | grep -qE '[/.]'; then
        # Remote container - already fetched to WORKDIR/fetched/
        local name=$(echo "$source" | sed 's|[/:]|_|g')
        local oci_src="${WORKDIR}/fetched/${name}"
        local tag=$(echo "$source" | grep -oE ':[^:]+$' | sed 's/^://' || echo "latest")
        local base_name=$(echo "$source" | sed 's|.*/||' | sed 's/:.*$//')
        local image_ref="${base_name}:${tag}"
    else
        # Local container - from DEPLOY_DIR
        local oci_src="${DEPLOY_DIR_IMAGE}/${source}-latest-oci"
        if [ ! -d "${oci_src}" ]; then
            oci_src="${DEPLOY_DIR_IMAGE}/${source}-oci"
        fi
        if [ ! -d "${oci_src}" ]; then
            oci_src="${DEPLOY_DIR_IMAGE}/${source}"
        fi
        local image_ref="${source}:latest"
    fi

    if [ ! -d "${oci_src}" ]; then
        bbfatal "Container OCI directory not found: ${oci_src}"
    fi

    # Copy OCI directory to build dir with image ref as name
    # Format: image_ref (e.g., busybox:1.36 or container-base:latest)
    local oci_name=$(echo "${image_ref}" | sed 's|[/:]|_|g')
    local oci_dest="${B}/oci/${oci_name}"

    bbnote "Collecting OCI: ${oci_src} -> ${oci_dest} (ref: ${image_ref})"
    cp -rL "${oci_src}" "${oci_dest}"

    # Store the image reference for later use
    echo "${oci_name}:${image_ref}" >> "${B}/oci-refs.txt"
}

do_install() {
    # Install OCI directories for container-cross-install to process
    # NO storage tars - vrunner runs once at rootfs time

    RUNTIME="${_BUNDLE_RUNTIME}"

    # Install OCI directories
    if [ -d "${B}/oci" ] && [ -n "$(ls -A ${B}/oci 2>/dev/null)" ]; then
        install -d ${D}${datadir}/container-bundles/${RUNTIME}/oci
        cp -r ${B}/oci/* ${D}${datadir}/container-bundles/${RUNTIME}/oci/
    fi

    # Install OCI references file
    if [ -f "${B}/oci-refs.txt" ]; then
        install -d ${D}${datadir}/container-bundles/${RUNTIME}
        install -m 0644 ${B}/oci-refs.txt \
            ${D}${datadir}/container-bundles/${RUNTIME}/${PN}.refs
    fi

    # Install metadata for autostart service generation
    if [ -f "${B}/bundle-metadata.txt" ]; then
        install -d ${D}${datadir}/container-bundles
        install -m 0644 ${B}/bundle-metadata.txt \
            ${D}${datadir}/container-bundles/${PN}.meta
    fi

    # Install custom service files from CONTAINER_SERVICE_FILE varflags
    # Format: container1=/path/to/file1;container2=/path/to/file2
    if [ -n "${_CONTAINER_SERVICE_FILE_MAP}" ]; then
        install -d ${D}${datadir}/container-bundles/${RUNTIME}/services
        echo "${_CONTAINER_SERVICE_FILE_MAP}" | tr ';' '\n' | while IFS='=' read -r container_name service_file; do
            [ -z "$container_name" ] && continue
            [ -z "$service_file" ] && continue

            if [ ! -f "$service_file" ]; then
                bbwarn "Custom service file not found: $service_file (for container $container_name)"
                continue
            fi

            # Sanitize container name for filename (replace / and : with _)
            local sanitized_name=$(echo "$container_name" | sed 's|[/:]|_|g')

            # Determine file extension based on runtime and source file
            local dest_file
            if [ "${RUNTIME}" = "docker" ]; then
                dest_file="${sanitized_name}.service"
            elif [ "${RUNTIME}" = "podman" ]; then
                dest_file="${sanitized_name}.container"
            else
                # Keep original extension
                dest_file="${sanitized_name}.$(echo "$service_file" | sed 's/.*\.//')"
            fi

            bbnote "Installing custom service file: $service_file -> services/${dest_file}"
            install -m 0644 "$service_file" \
                ${D}${datadir}/container-bundles/${RUNTIME}/services/${dest_file}
        done
    fi
}

FILES:${PN} = "${datadir}/container-bundles"

# mcdepends set conditionally in __anonymous() above

# ===========================================================================
# Optional Deploy for OCI Base Layer Usage
# ===========================================================================
#
# When CONTAINER_BUNDLE_DEPLOY = "1", this class also deploys fetched remote
# containers to DEPLOY_DIR_IMAGE for use as base layers with OCI_BASE_IMAGE.
#
# This enables dual-use recipes that both:
#   1. Create installable packages for target container storage
#   2. Provide OCI base layers for building layered containers
#
# Example:
#   # alpine-oci-base.bb
#   inherit container-bundle
#   CONTAINER_BUNDLES = "docker.io/library/alpine:3.19"
#   CONTAINER_DIGESTS[docker.io_library_alpine_3.19] = "sha256:..."
#   CONTAINER_BUNDLE_DEPLOY = "1"
#
#   # Then in another recipe:
#   OCI_BASE_IMAGE = "alpine-oci-base"
#
CONTAINER_BUNDLE_DEPLOY ?= ""

python () {
    if d.getVar('CONTAINER_BUNDLE_DEPLOY') == "1":
        # Inherit deploy class dynamically
        bb.build.addtask('do_deploy', 'do_build', 'do_compile', d)
}

do_deploy() {
    if [ "${CONTAINER_BUNDLE_DEPLOY}" != "1" ]; then
        bbnote "CONTAINER_BUNDLE_DEPLOY not set, skipping deploy"
        return 0
    fi

    # Deploy fetched OCI directories to DEPLOY_DIR_IMAGE for use as base layers
    # Format: ${PN}-latest-oci/ (matches what image-oci.bbclass expects)

    if [ ! -d "${WORKDIR}/fetched" ]; then
        bbwarn "No fetched containers to deploy"
        return 0
    fi

    # Find the first (primary) fetched OCI directory
    oci_dir=$(ls -d ${WORKDIR}/fetched/*/ 2>/dev/null | head -1)
    if [ -z "$oci_dir" ] || [ ! -f "$oci_dir/index.json" ]; then
        bbfatal "No valid OCI directory found in ${WORKDIR}/fetched/"
    fi

    bbnote "Deploying OCI base layer: $oci_dir -> ${DEPLOYDIR}/${PN}-latest-oci"

    install -d ${DEPLOYDIR}
    cp -rL "$oci_dir" ${DEPLOYDIR}/${PN}-${PV}-oci

    # Create symlinks for OCI_BASE_IMAGE lookup
    ln -sfn ${PN}-${PV}-oci ${DEPLOYDIR}/${PN}-latest-oci
}
do_deploy[dirs] = "${DEPLOYDIR}"

# Only add sstate for deploy when enabled
SSTATE_SKIP_CREATION:task-deploy = "${@'' if d.getVar('CONTAINER_BUNDLE_DEPLOY') == '1' else '1'}"
