#
# This image class creates an oci image spec directory from a generated
# rootfs. The contents of the rootfs do not matter (i.e. they need not be
# container optimized), but by using the container image type and small
# footprint images, we can create directly executable container images.
#
# Once the tarball (or oci image directory) has been created of the OCI
# image, it can be manipulated by standard tools. For example, to create a
# runtime bundle from the oci image, the following can be done:
#
# Assuming the image name is "container-base":
#
#   If the oci image is a tarball, extract it to a temporary directory:
#     % mkdir -p t && tar xvf container-base-latest-oci.tar -C t
#
#   Create the bundle from the deployed OCI directory symlink (resolve first):
#     % oci-image-tool create --ref name=latest "$(readlink -f container-base-latest-oci)" container-base-oci-bundle
#
#   (If using an extracted tar layout in ./t, this also works:
#     % oci-image-tool create --ref name=latest t container-base-oci-bundle)
#
#   NOTE: oci-image-tool may generate a minimal config.json that lacks the
#   runtime mounts expected by modern runc. Generate a current runc spec and
#   merge the image-derived process settings:
#
#     % cd container-base-oci-bundle
#     % cp config.json config.image.json
#     % rm -f config.json
#     % XDG_RUNTIME_DIR=/tmp runc spec
#     % jq -s '\''.[0] as $img | .[1] as $base | $base |
#         .root.path = ($img.root.path // "rootfs") |
#         .process.args = ($img.process.args // $base.process.args) |
#         .process.cwd = ($img.process.cwd // $base.process.cwd) |
#         .process.user = ($img.process.user // $base.process.user) |
#         .process.env = (($base.process.env // []) + ($img.process.env // []) | unique)'\'' \
#         config.image.json config.json > config.merged.json && mv config.merged.json config.json
#     % cd ..
#
#   If your build host architecture matches the target, you can execute the unbundled
#   container with runc:
#     % sudo runc run -b container-base-oci-bundle ctr-build
# / % uname -a
# Linux mrsdalloway 4.18.0-25-generic #26-Ubuntu SMP Mon Jun 24 09:32:08 UTC 2019 x86_64 GNU/Linux
#
#   Cleanup between runs (if needed):
#     % sudo runc delete -f ctr-build || true
#     % sudo umount -Rl container-base-oci-bundle/rootfs 2>/dev/null || true
#
#   Alternatively, the bundle can be created with umoci (use --rootless if sudo is not available)
#     % sudo umoci unpack --image container-base-<arch>-<stamp>.rootfs-oci:latest container-base-oci-bundle
#
#   Or to copy (push) the oci image to a docker registry, skopeo can be used (vary the
#   tag based on the created oci image:
#
#     % skopeo copy --dest-creds <username>:<password> oci:container-base-<arch>-<stamp>:latest docker://zeddii/container-base
#
# We'd probably get this through the container image typdep, but just
# to be sure, we'll repeat it here.
ROOTFS_BOOTSTRAP_INSTALL = ""
# we want container and tar.bz2's to be created
IMAGE_TYPEDEP:oci = "container tar.bz2"

# sloci is the script/project that will create the oci image
# OCI_IMAGE_BACKEND ?= "sloci-image"
OCI_IMAGE_BACKEND ?= "umoci"
do_image_oci[depends] += "${OCI_IMAGE_BACKEND}-native:do_populate_sysroot"
# jq-native is needed for the merged-usr whiteout fix
do_image_oci[depends] += "jq-native:do_populate_sysroot"
# Package manager native tools for multi-layer mode with package installation
OCI_PM_DEPENDS = "${@oci_get_pm_depends(d)}"
do_image_oci[depends] += "${OCI_PM_DEPENDS}"

def oci_get_pm_depends(d):
    """Get native package manager dependency for multi-layer mode."""
    if d.getVar('OCI_LAYER_MODE') != 'multi':
        return ''
    if 'packages' not in (d.getVar('OCI_LAYERS') or ''):
        return ''
    # rsync-native is needed to copy pre-installed packages to bundle rootfs
    deps = 'rsync-native:do_populate_sysroot'
    pkg_type = d.getVar('IMAGE_PKGTYPE') or 'rpm'
    if pkg_type == 'rpm':
        deps += ' dnf-native:do_populate_sysroot createrepo-c-native:do_populate_sysroot'
    elif pkg_type == 'ipk':
        deps += ' opkg-native:do_populate_sysroot'
    elif pkg_type == 'deb':
        deps += ' apt-native:do_populate_sysroot'
    return deps

#
# image type configuration block
#
OCI_IMAGE_AUTHOR ?= "${PATCH_GIT_USER_NAME}"
OCI_IMAGE_AUTHOR_EMAIL ?= "${PATCH_GIT_USER_EMAIL}"

OCI_IMAGE_TAG ?= "latest"
OCI_IMAGE_RUNTIME_UID ?= ""

OCI_IMAGE_ARCH ?= "${@oe.go.map_arch(d.getVar('TARGET_ARCH'))}"
OCI_IMAGE_SUBARCH ?= "${@oci_map_subarch(d.getVar('TARGET_ARCH'), d.getVar('TUNE_FEATURES'), d)}"

# OCI_IMAGE_ENTRYPOINT: If set, this command always runs (args appended).
# OCI_IMAGE_CMD: Default command (replaced when user passes arguments).
# Most base images use CMD only for flexibility. Use ENTRYPOINT for wrapper scripts.
OCI_IMAGE_ENTRYPOINT ?= ""
OCI_IMAGE_ENTRYPOINT_ARGS ?= ""
OCI_IMAGE_CMD ?= "/bin/sh"
OCI_IMAGE_WORKINGDIR ?= ""
OCI_IMAGE_STOPSIGNAL ?= ""

# List of ports to expose from a container running this image:
#  PORT[/PROT]  
#     format: <port>/tcp, <port>/udp, or <port> (same as <port>/tcp).
OCI_IMAGE_PORTS ?= ""

# key=value list of labels (user-defined)
OCI_IMAGE_LABELS ?= ""
# key=value list of environment variables
OCI_IMAGE_ENV_VARS ?= ""

# =============================================================================
# Build-time metadata for traceability
# =============================================================================
#
# These variables embed source info into OCI image labels for traceability.
# Standard OCI annotations are used: https://github.com/opencontainers/image-spec/blob/main/annotations.md
#
# OCI_IMAGE_APP_RECIPE: Recipe name for the "main application" in the container.
#   If set, future versions may auto-extract SRCREV/branch from this recipe.
#   For now, it's documentation and a hook point.
#
# OCI_IMAGE_REVISION: Git commit SHA (short or full).
#   - If set: uses this value
#   - If empty: auto-detects from TOPDIR git repo
#   - Set to "none" to disable
#
# OCI_IMAGE_BRANCH: Git branch name.
#   - If set: uses this value
#   - If empty: auto-detects from TOPDIR git repo
#   - Set to "none" to disable
#
# OCI_IMAGE_BUILD_DATE: ISO 8601 timestamp.
#   - Auto-generated at build time
#
# These become standard OCI labels:
#   org.opencontainers.image.revision = OCI_IMAGE_REVISION
#   org.opencontainers.image.ref.name = OCI_IMAGE_BRANCH
#   org.opencontainers.image.created = OCI_IMAGE_BUILD_DATE
#   org.opencontainers.image.version = PV (if meaningful)

# Application recipe for traceability (documentation/future use)
OCI_IMAGE_APP_RECIPE ?= ""

# Explicit overrides - if set, these are used instead of auto-detection
# Set to "none" to disable a specific label
OCI_IMAGE_REVISION ?= ""
OCI_IMAGE_BRANCH ?= ""
OCI_IMAGE_BUILD_DATE ?= ""

# Enable/disable auto-detection of git metadata (set to "0" to disable)
OCI_IMAGE_AUTO_LABELS ?= "1"

# =============================================================================
# Multi-Layer OCI Support
# =============================================================================
#
# OCI_BASE_IMAGE: Base image to build on top of
#   - Recipe name: "container-base" (uses local recipe's OCI output)
#   - Path: "/path/to/oci-dir" (uses existing OCI layout)
#   - Registry URL: "docker.io/library/alpine:3.19" (fetches external image)
#
# OCI_LAYER_MODE: How to create layers
#   - "single" (default): Single layer with complete rootfs (backward compatible)
#   - "multi": Multiple layers from OCI_LAYERS definitions
#
# When OCI_BASE_IMAGE is set:
#   - Base image layers are preserved
#   - New content from IMAGE_ROOTFS is added as additional layer(s)
#
OCI_BASE_IMAGE ?= ""
OCI_BASE_IMAGE_TAG ?= "latest"
OCI_LAYER_MODE ?= "single"

# =============================================================================
# Multi-Layer Mode (OCI_LAYER_MODE = "multi")
# =============================================================================
#
# OCI_LAYERS defines explicit layers when OCI_LAYER_MODE = "multi".
# Each layer is defined as: "name:type:content"
#
# Layer Types:
#   packages    - Install packages using Yocto's package manager
#   directories - Copy specific directories from IMAGE_ROOTFS (delta-only)
#   files       - Copy specific files from IMAGE_ROOTFS (delta-only)
#   host        - Copy files from build machine filesystem (outside Yocto)
#
# Format: Space-separated list of layer definitions
#   OCI_LAYERS = "layer1:type:content layer2:type:content ..."
#
# For packages type, content is package names (use + as delimiter):
#   "base:packages:base-files+busybox+netbase"
#
# For directories/files type, content is paths (use + as delimiter):
#   "app:directories:/opt/myapp+/etc/myapp"
#   "config:files:/etc/myapp.conf+/etc/default/myapp"
#
#   NOTE: directories/files only copy content NOT already present in
#   earlier layers (delta-only), avoiding duplication with packages layers.
#
# For host type, content is source:dest pairs (use + as delimiter):
#   "certs:host:/etc/ssl/certs/my-ca.crt:/etc/ssl/certs/my-ca.crt"
#   "config:host:/home/builder/config:/etc/myapp/config+/home/builder/keys:/etc/myapp/keys"
#
#   WARNING: host layers copy content from the build machine that is NOT
#   part of the Yocto build. This affects reproducibility - the build output
#   depends on the state of the build machine. Use sparingly for deployment-
#   specific config, keys, or certificates that cannot be packaged.
#
# Note: Use + as delimiter because ; is interpreted as shell command separator
#
# Example:
#   OCI_LAYER_MODE = "multi"
#   OCI_LAYERS = "\
#       base:packages:base-files+base-passwd+netbase+busybox \
#       python:packages:python3+python3-pip \
#       app:directories:/opt/myapp \
#       certs:host:/etc/ssl/certs/my-ca.crt:/etc/ssl/certs/ \
#   "
#
# Result: 4 layers (base, python, app, certs) plus any base image layers
#
OCI_LAYERS ?= ""

# =============================================================================
# Layer Caching (for multi-layer mode)
# =============================================================================
#
# OCI_LAYER_CACHE: Enable/disable layer caching ("1" or "0")
#   When enabled, pre-installed package layers are cached to avoid
#   reinstalling packages on subsequent builds.
#
# OCI_LAYER_CACHE_DIR: Directory for storing cached layers
#   Default: ${TOPDIR}/oci-layer-cache/${MACHINE}
#   Cache is keyed by: layer definition + package versions + architecture
#
# Cache key components:
#   - Layer name and type
#   - Sorted package list
#   - Package versions (from PKGDATA_DIR)
#   - MACHINE and TUNE_PKGARCH
#
# Cache invalidation:
#   - Any package version change invalidates layers containing that package
#   - Layer definition changes invalidate that specific layer
#   - MACHINE/arch changes use separate cache directories
#
OCI_LAYER_CACHE ?= "1"
OCI_LAYER_CACHE_DIR ?= "${TOPDIR}/oci-layer-cache/${MACHINE}"

# whether the oci image dir should be left as a directory, or
# bundled into a tarball.
OCI_IMAGE_TAR_OUTPUT ?= "true"

# Generate a subarch that is appropriate to OCI image
# types. This is typically only ARM architectures at the
# moment.
def oci_map_subarch(a, f, d):
    import re
    if re.match('arm.*', a):
        if 'armv7' in f:
            return 'v7'
        elif 'armv6' in f:
            return 'v6'
        elif 'armv5' in f:
            return 'v5'
            return ''
    return ''

# =============================================================================
# Base Image Resolution and Dependency Setup
# =============================================================================

def oci_resolve_base_image(d):
    """Resolve OCI_BASE_IMAGE to determine its type.

    Returns dict with 'type' key:
      - {'type': 'recipe', 'name': 'container-base'}
      - {'type': 'path', 'path': '/path/to/oci-dir'}
      - {'type': 'remote', 'url': 'docker.io/library/alpine:3.19'}
      - None if no base image
    """
    base = d.getVar('OCI_BASE_IMAGE') or ''
    if not base:
        return None

    # Check if it's a path (starts with /)
    if base.startswith('/'):
        return {'type': 'path', 'path': base}

    # Check if it looks like a registry URL (contains / or has registry prefix)
    if '/' in base or '.' in base.split(':')[0]:
        return {'type': 'remote', 'url': base}

    # Assume it's a recipe name
    return {'type': 'recipe', 'name': base}

python __anonymous() {
    import os

    backend = d.getVar('OCI_IMAGE_BACKEND') or 'umoci'
    base_image = d.getVar('OCI_BASE_IMAGE') or ''
    layer_mode = d.getVar('OCI_LAYER_MODE') or 'single'

    # sloci doesn't support multi-layer
    if backend == 'sloci-image':
        if layer_mode != 'single' or base_image:
            bb.fatal("Multi-layer OCI requires umoci backend. "
                     "Set OCI_IMAGE_BACKEND = 'umoci' or remove OCI_BASE_IMAGE")

    # Validate multi-layer mode configuration and add dependencies
    if layer_mode == 'multi':
        oci_layers = d.getVar('OCI_LAYERS') or ''
        if not oci_layers.strip():
            bb.fatal("OCI_LAYER_MODE = 'multi' requires OCI_LAYERS to be defined")

        has_packages_layer = False
        host_layer_warnings = []

        # Parse and validate layer definitions
        for layer_def in oci_layers.split():
            parts = layer_def.split(':')
            if len(parts) < 3:
                bb.fatal(f"Invalid OCI_LAYERS entry '{layer_def}': "
                         "format is 'name:type:content'")
            layer_name, layer_type, layer_content = parts[0], parts[1], ':'.join(parts[2:])
            if layer_type not in ('packages', 'directories', 'files', 'host'):
                bb.fatal(f"Invalid layer type '{layer_type}' in '{layer_def}': "
                         "must be 'packages', 'directories', 'files', or 'host'")
            if layer_type == 'packages':
                has_packages_layer = True
            elif layer_type == 'host':
                # Validate host layer format and collect warnings
                # Format: source:dest pairs separated by +
                for pair in layer_content.replace('+', ' ').split():
                    if ':' not in pair:
                        bb.fatal(f"Invalid host layer content '{pair}' in '{layer_def}': "
                                 "format is 'source_path:dest_path'")
                    src_path = pair.rsplit(':', 1)[0]
                    host_layer_warnings.append(f"  Layer '{layer_name}': {src_path}")

        # Emit warning for host layers (content from build machine, not Yocto)
        if host_layer_warnings:
            bb.warn("OCI image includes content from build machine filesystem (host layers).\n"
                    "This content is NOT part of the Yocto build and affects reproducibility.\n"
                    "The build output will depend on the state of the build machine.\n"
                    "Host paths used:\n" + "\n".join(host_layer_warnings))

        # Add package manager native dependency if using 'packages' layer type
        if has_packages_layer:
            pkg_type = d.getVar('IMAGE_PKGTYPE') or 'ipk'
            if pkg_type == 'ipk':
                d.appendVarFlag('do_image_oci', 'depends',
                    " opkg-native:do_populate_sysroot opkg-utils-native:do_populate_sysroot")
                bb.debug(1, "OCI: Added opkg-native dependency for packages layers")
            elif pkg_type == 'rpm':
                d.appendVarFlag('do_image_oci', 'depends',
                    " dnf-native:do_populate_sysroot")
                bb.debug(1, "OCI: Added dnf-native dependency for packages layers")
            elif pkg_type == 'deb':
                d.appendVarFlag('do_image_oci', 'depends',
                    " apt-native:do_populate_sysroot")
                bb.debug(1, "OCI: Added apt-native dependency for packages layers")

            # Extract all packages from OCI_LAYERS and add do_package_write dependencies
            # This allows IMAGE_INSTALL = "" for pure multi-layer builds
            all_packages = set()
            for layer_def in oci_layers.split():
                parts = layer_def.split(':')
                if len(parts) >= 3 and parts[1] == 'packages':
                    layer_content = ':'.join(parts[2:])
                    # Use + as delimiter (not ; which is shell command separator)
                    for pkg in layer_content.replace('+', ' ').split():
                        all_packages.add(pkg)

            if all_packages:
                # Note: Packages need to be in IMAGE_INSTALL to trigger builds
                # via do_rootfs recrdeptask. We just log which packages we found.
                bb.debug(1, f"OCI multi-layer: Found packages in OCI_LAYERS: {' '.join(all_packages)}")

    # Resolve base image and set up dependencies
    if base_image:
        resolved = oci_resolve_base_image(d)
        if resolved:
            if resolved['type'] == 'recipe':
                # Add dependency on base recipe's OCI output
                # Use do_build as it works for both image recipes and oci-fetch recipes
                base_recipe = resolved['name']
                d.setVar('_OCI_BASE_RECIPE', base_recipe)
                d.appendVarFlag('do_image_oci', 'depends',
                    f" {base_recipe}:do_build rsync-native:do_populate_sysroot")
                bb.debug(1, f"OCI: Using base image from recipe: {base_recipe}")

            elif resolved['type'] == 'path':
                d.setVar('_OCI_BASE_PATH', resolved['path'])
                d.appendVarFlag('do_image_oci', 'depends',
                    " rsync-native:do_populate_sysroot")
                bb.debug(1, f"OCI: Using base image from path: {resolved['path']}")

            elif resolved['type'] == 'remote':
                # Remote URLs are not supported directly - use a container-bundle recipe
                remote_url = resolved['url']
                # Create sanitized key for CONTAINER_DIGESTS varflag
                sanitized_key = remote_url.replace('/', '_').replace(':', '_')
                bb.fatal(f"Remote base images cannot be used directly: {remote_url}\n\n"
                         f"Create a container-bundle recipe to fetch the external image:\n\n"
                         f"  # recipes-containers/oci-base-images/my-base.bb\n"
                         f"  inherit container-bundle\n"
                         f"  CONTAINER_BUNDLES = \"{remote_url}\"\n"
                         f"  CONTAINER_DIGESTS[{sanitized_key}] = \"sha256:...\"\n"
                         f"  CONTAINER_BUNDLE_DEPLOY = \"1\"\n\n"
                         f"Get digest with: skopeo inspect docker://{remote_url} | jq -r '.Digest'\n\n"
                         f"Then use: OCI_BASE_IMAGE = \"my-base\"")
}

# =============================================================================
# Multi-Layer Package Installation using Yocto's PM Classes
# =============================================================================
#
# This function uses the same package management infrastructure as do_rootfs,
# ensuring consistency and maintainability.

def oci_install_layer_packages(d, layer_rootfs, layer_packages, layer_name):
    """
    Install packages to a layer rootfs using Yocto's package manager classes.

    This uses the same PM infrastructure as do_rootfs for consistency.

    Args:
        d: BitBake datastore
        layer_rootfs: Path to the layer's rootfs directory
        layer_packages: Space-separated list of packages to install
        layer_name: Name of the layer (for logging)
    """
    import os
    import oe.path

    packages = layer_packages.split()
    if not packages:
        bb.note(f"OCI: No packages to install for layer {layer_name}")
        return

    bb.note(f"OCI: Installing packages for layer '{layer_name}': {' '.join(packages)}")

    pkg_type = d.getVar('IMAGE_PKGTYPE') or 'rpm'

    # Ensure layer rootfs directory exists
    bb.utils.mkdirhier(layer_rootfs)

    if pkg_type == 'rpm':
        from oe.package_manager.rpm import RpmPM

        # Create PM instance for layer rootfs
        pm = RpmPM(d,
                   layer_rootfs,
                   d.getVar('TARGET_VENDOR'),
                   task_name='oci-layer',
                   filterbydependencies=False)

        # Setup configs in layer rootfs
        pm.create_configs()

        # Generate/update repo indexes
        pm.write_index()

        # Install packages
        # Use attempt_only=True to allow unresolved deps (resolved in later layers)
        try:
            pm.install(packages, attempt_only=True)
        except Exception as e:
            bb.warn(f"OCI: Package installation had issues (may be resolved in later layers): {e}")

    elif pkg_type == 'ipk':
        from oe.package_manager.ipk import OpkgPM

        # Create config file for this layer
        config_file = os.path.join(d.getVar('WORKDIR'), f'opkg-{layer_name}.conf')
        archs = d.getVar('PACKAGE_ARCHS')

        # Create PM instance
        pm = OpkgPM(d,
                    layer_rootfs,
                    config_file,
                    archs,
                    task_name='oci-layer',
                    filterbydependencies=False)

        # Write indexes
        pm.write_index()

        # Install packages
        try:
            pm.install(packages, attempt_only=True)
        except Exception as e:
            bb.warn(f"OCI: Package installation had issues (may be resolved in later layers): {e}")

    elif pkg_type == 'deb':
        bb.warn("OCI: deb package type not yet fully implemented for multi-layer")

    else:
        bb.fatal(f"OCI: Unsupported package type: {pkg_type}")

    bb.note(f"OCI: Package installation complete for layer '{layer_name}'")

# the IMAGE_CMD:oci comes from the .inc
OCI_IMAGE_BACKEND_INC ?= "${@"image-oci-" + "${OCI_IMAGE_BACKEND}" + ".inc"}"
include ${OCI_IMAGE_BACKEND_INC}
