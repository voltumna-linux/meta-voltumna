# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# container-cross-install.bbclass
# ===========================================================================
# Cross-architecture container deployment class
# ===========================================================================
#
# This class enables bundling containers into target images during build time.
# It uses QEMU with a pre-built initramfs to process containers built for
# different architectures (cross-compilation safe).
#
# Usage (in image recipe, e.g., core-image-minimal.bbappend):
#   inherit container-cross-install
#
# Configuration (in local.conf or image recipe):
#   BUNDLED_CONTAINERS = "container-base:docker myapp:podman:autostart"
#
# Container format: name:runtime[:autostart][:external]
#   - name: Container recipe name OR OCI directory name in DEPLOY_DIR_IMAGE
#   - runtime: docker or podman
#   - autostart: Optional. Creates systemd service to start on boot:
#       * autostart     - alias for unless-stopped (recommended)
#       * always        - always restart container
#       * unless-stopped - restart unless manually stopped
#       * on-failure    - restart only on non-zero exit code
#   - external: Optional tag for third-party containers (no dependency generated)
#
# Automatic dependency generation:
#   - Dependencies on container recipes are auto-generated at parse time
#   - If name ends in -oci, recipe name is derived (strip -latest-oci or -oci)
#   - Use :external tag to skip dependency for third-party blobs
#
# OCI directory resolution:
#   - If name ends in -oci, use directly from DEPLOY_DIR_IMAGE
#   - Otherwise, search: name-latest-oci -> name-oci (fallback)
#
# Examples:
#   BUNDLED_CONTAINERS = "container-base:docker"           # auto-dep, no autostart
#   BUNDLED_CONTAINERS = "myapp:podman:autostart"          # auto-dep, autostart
#   BUNDLED_CONTAINERS = "vendor-blob:docker:external"     # no dep, third-party
#   BUNDLED_CONTAINERS = "vendor-blob:docker:autostart:external"  # no dep, autostart
#   # Legacy format still supported:
#   BUNDLED_CONTAINERS = "container-base-latest-oci:docker"  # auto-dep (derived)
#
# Generated autostart files:
#   Docker: /etc/systemd/system/container-<name>.service (enabled)
#   Podman: /etc/containers/systemd/<name>.container (Quadlet format)
#
# The class uses vdkr/vpdmn initramfs blobs built via multiconfig (mcdepends).
# These contain Docker or Podman tools respectively and are built by
# vdkr-initramfs-create and vpdmn-initramfs-create recipes.
#
# ===========================================================================
# Choosing Between BUNDLED_CONTAINERS and container-bundle Packages
# ===========================================================================
#
# There are two ways to bundle containers into a host image:
#
#   1. BUNDLED_CONTAINERS variable (this class, simpler)
#      Set in local.conf or image recipe - no extra recipe needed
#
#   2. container-bundle packages
#      Create a bundle recipe that inherits container-bundle.bbclass,
#      then add the package to IMAGE_INSTALL
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
# Use container-bundle.bbclass when you need:
#   - Remote container fetching via skopeo
#   - A distributable/versioned package of containers
#   - To share the same bundle across multiple different host images
#
# ===========================================================================
# Integration with container-bundle.bbclass
# ===========================================================================
#
# This class also processes packages created by container-bundle.bbclass:
#   1. merge_installed_bundles() runs as ROOTFS_POSTPROCESS_COMMAND
#   2. Scans ${datadir}/container-bundles/{docker,podman}/oci/ and *.refs files
#   3. Runs vrunner --batch-import once to create storage, extracts to rootfs
#   4. Reads *.meta files for autostart service generation
#
# The runtime is determined by the subdirectory (docker/ vs podman/),
# which is set by container-bundle.bbclass based on CONTAINER_BUNDLE_RUNTIME.
#
# ===========================================================================
# Custom Service Files (CONTAINER_SERVICE_FILE)
# ===========================================================================
#
# For containers requiring specific startup configuration (ports, volumes,
# capabilities, dependencies), provide custom service files instead of
# auto-generated ones using the CONTAINER_SERVICE_FILE varflag:
#
#   CONTAINER_SERVICE_FILE[container-name] = "${UNPACKDIR}/myservice.service"
#   CONTAINER_SERVICE_FILE[other-container] = "${UNPACKDIR}/other.container"
#
# Usage in image recipe:
#   SRC_URI += "file://myapp.service"
#   BUNDLED_CONTAINERS = "myapp-container:docker:autostart"
#   CONTAINER_SERVICE_FILE[myapp-container] = "${UNPACKDIR}/myapp.service"
#
# The custom file replaces the auto-generated service. For Docker, provide
# a .service file; for Podman, provide a .container Quadlet file.
#
# See docs/container-bundling.md for detailed examples.
#
# See also: container-bundle.bbclass

# Inherit shared functions for multiconfig/machine/arch mapping
inherit container-common

# Default runtime based on CONTAINER_PROFILE (same logic as container-bundle.bbclass)
def get_default_container_runtime(d):
    """Determine default container runtime from CONTAINER_PROFILE"""
    profile = d.getVar('CONTAINER_PROFILE') or 'docker'
    if profile in ['podman']:
        return 'podman'
    # docker, containerd, k3s-*, default all use docker storage format
    return 'docker'

CONTAINER_DEFAULT_RUNTIME ?= "${@get_default_container_runtime(d)}"

# Dependencies on native tools
# vcontainer-native provides vrunner.sh
# Blobs come from multiconfig builds (vdkr-initramfs-create, vpdmn-initramfs-create)
DEPENDS += "qemuwrapper-cross qemu-system-native skopeo-native"
DEPENDS += "vcontainer-native coreutils-native"

VRUNTIME_MULTICONFIG = "${@get_vruntime_multiconfig(d)}"
VRUNTIME_MACHINE = "${@get_vruntime_machine(d)}"

# Generate dependencies for BUNDLED_CONTAINERS at parse time
# Format: name:runtime[:autostart][:external]
# - If :external present, no dependency generated (third-party blob)
# - If name ends in -oci, derive recipe name and generate dependency
# - Otherwise, generate dependency on name:do_image_complete
python __anonymous() {
    # Conditionally set mcdepends when vruntime multiconfig is configured
    # (avoids parse errors when BBMULTICONFIG is not set, e.g. yocto-check-layer)
    vruntime_mc = d.getVar('VRUNTIME_MULTICONFIG')
    bbmulticonfig = (d.getVar('BBMULTICONFIG') or "").split()
    if vruntime_mc and vruntime_mc in bbmulticonfig:
        d.setVarFlag('do_rootfs', 'mcdepends',
            'mc::%s:vdkr-initramfs-create:do_deploy mc::%s:vpdmn-initramfs-create:do_deploy' % (vruntime_mc, vruntime_mc))

    bundled = (d.getVar('BUNDLED_CONTAINERS') or "").split()
    if not bundled:
        return

    deps = ""
    for entry in bundled:
        parts = entry.split(':')
        container_name = parts[0]

        # Check for :external tag (can be in position 3 or 4)
        is_external = 'external' in parts

        # Skip dependency for external containers
        if is_external:
            continue

        # Derive recipe name from OCI dir name if needed
        recipe_name = container_name
        if container_name.endswith('-latest-oci'):
            recipe_name = container_name[:-11]  # strip -latest-oci
        elif container_name.endswith('-oci'):
            recipe_name = container_name[:-4]   # strip -oci

        # Generate dependency
        deps += f" {recipe_name}:do_image_complete"

    if deps:
        d.appendVarFlag('do_rootfs', 'depends', deps)

    # Auto-add registry config package when secure registry is configured
    # This ensures the target can pull from the registry at runtime
    if d.getVar('CONTAINER_REGISTRY_SECURE') == '1':
        # Determine which config package based on container engine
        engine = d.getVar('VIRTUAL-RUNTIME_container_engine') or ''
        if 'docker' in engine:
            d.appendVar('IMAGE_INSTALL', ' docker-registry-config')
        elif engine in ('podman', 'containerd', 'cri-o'):
            d.appendVar('IMAGE_INSTALL', ' container-oci-registry-config')
}

# Build CONTAINER_SERVICE_FILE_MAP from varflags for shell access
# Format: container1=/path/to/file1;container2=/path/to/file2
def get_container_service_file_map(d):
    """Build a semicolon-separated map of container names to custom service files"""
    bundled = (d.getVar('BUNDLED_CONTAINERS') or "").split()
    if not bundled:
        return ""

    mappings = []
    for entry in bundled:
        parts = entry.split(':')
        container_name = parts[0]
        custom_file = d.getVarFlag('CONTAINER_SERVICE_FILE', container_name)
        if custom_file:
            mappings.append(f"{container_name}={custom_file}")

    return ";".join(mappings)

CONTAINER_SERVICE_FILE_MAP = "${@get_container_service_file_map(d)}"

# Path to vrunner.sh from vcontainer-native
VRUNNER_PATH = "${STAGING_BINDIR_NATIVE}/vrunner.sh"

# Blobs come from multiconfig's DEPLOY_DIR (built by mcdepends on vdkr-initramfs-create)
# Multiconfig uses separate TMPDIR, so deploy path is:
#   ${TOPDIR}/tmp-${VRUNTIME_MULTICONFIG}/deploy/images/${VRUNTIME_MACHINE}/
# Blobs are in runtime/arch subdirectories: ${BLOB_DIR}/${ARCH}/ (e.g., x86_64/, aarch64/)
VDKR_BLOB_DIR = "${TOPDIR}/tmp-${VRUNTIME_MULTICONFIG}/deploy/images/${VRUNTIME_MACHINE}/vdkr"
VPDMN_BLOB_DIR = "${TOPDIR}/tmp-${VRUNTIME_MULTICONFIG}/deploy/images/${VRUNTIME_MACHINE}/vpdmn"

bundle_containers[network] = "1"
do_testsdkext[nostamp] = "1"

# Map TARGET_ARCH to QEMU architecture names
def get_qemu_arch(d):
    """Map Yocto TARGET_ARCH to QEMU architecture name"""
    arch = d.getVar('TARGET_ARCH')
    arch_map = {
        'aarch64': 'aarch64',
        'arm': 'arm',
        'x86_64': 'x86_64',
        'i686': 'i386',
        'i586': 'i386',
    }
    return arch_map.get(arch, arch)

QEMU_ARCH = "${@get_qemu_arch(d)}"

# Map TARGET_ARCH to kernel image name
def get_kernel_name(d):
    """Map Yocto TARGET_ARCH to kernel image filename"""
    arch = d.getVar('TARGET_ARCH')
    kernel_map = {
        'aarch64': 'Image',
        'arm': 'zImage',
        'x86_64': 'bzImage',
        'i686': 'bzImage',
        'i586': 'bzImage',
    }
    return kernel_map.get(arch, 'Image')

KERNEL_IMAGETYPE_QEMU = "${@get_kernel_name(d)}"

# BLOB_ARCH uses get_blob_arch() from container-common.bbclass
BLOB_ARCH = "${@get_blob_arch(d)}"

# Timeout scaling: base startup + per-container time
# QEMU boot is ~180s, larger containers (multi-layer with deps) can take ~600s
CONTAINER_IMPORT_TIMEOUT_BASE ?= "180"
CONTAINER_IMPORT_TIMEOUT_PER ?= "600"

# ============================================================================
# Merge container bundles installed via IMAGE_INSTALL
# This function processes packages created by container-bundle.bbclass
# ============================================================================
merge_installed_bundles() {
    # Disable errexit - we handle errors explicitly
    set +e

    BUNDLES_DIR="${IMAGE_ROOTFS}${datadir}/container-bundles"

    if [ ! -d "${BUNDLES_DIR}" ]; then
        bbnote "No container bundles found in ${BUNDLES_DIR}"
        return 0
    fi

    bbnote "Processing installed container bundles from ${BUNDLES_DIR}"

    # Collect all OCI directories from bundle packages
    # Bundle packages now contain OCI directories, not storage tars
    # We run vrunner ONCE with all containers to create a single storage tar

    local docker_containers=""
    local podman_containers=""

    # Collect Docker OCI directories and refs
    if [ -d "${BUNDLES_DIR}/docker/oci" ]; then
        for refs_file in ${BUNDLES_DIR}/docker/*.refs; do
            [ -f "$refs_file" ] || continue
            while IFS=: read -r oci_name image_ref; do
                [ -z "$oci_name" ] && continue
                local oci_path="${BUNDLES_DIR}/docker/oci/${oci_name}"
                if [ -d "$oci_path" ]; then
                    # Format for vrunner batch-import: path:image:tag
                    docker_containers="${docker_containers} ${oci_path}:${image_ref}"
                    bbnote "Docker container: ${oci_path} -> ${image_ref}"
                fi
            done < "$refs_file"
        done
    fi

    # Collect Podman OCI directories and refs
    if [ -d "${BUNDLES_DIR}/podman/oci" ]; then
        for refs_file in ${BUNDLES_DIR}/podman/*.refs; do
            [ -f "$refs_file" ] || continue
            while IFS=: read -r oci_name image_ref; do
                [ -z "$oci_name" ] && continue
                local oci_path="${BUNDLES_DIR}/podman/oci/${oci_name}"
                if [ -d "$oci_path" ]; then
                    podman_containers="${podman_containers} ${oci_path}:${image_ref}"
                    bbnote "Podman container: ${oci_path} -> ${image_ref}"
                fi
            done < "$refs_file"
        done
    fi

    # Import all Docker containers via vrunner (single invocation)
    if [ -n "${docker_containers}" ]; then
        bbnote "Importing Docker containers via vrunner: ${docker_containers}"

        local docker_storage="${WORKDIR}/docker-storage-$$.tar"

        # Calculate timeout: base startup + per-container time
        local num_containers=$(echo "${docker_containers}" | wc -w)
        local import_timeout=$(expr ${CONTAINER_IMPORT_TIMEOUT_BASE} + $num_containers \* ${CONTAINER_IMPORT_TIMEOUT_PER})
        bbnote "Docker batch import timeout: ${import_timeout}s (${num_containers} containers)"

        ${VRUNNER_PATH} \
            --no-daemon \
            --runtime docker \
            --arch ${BLOB_ARCH} \
            --blob-dir ${VDKR_BLOB_DIR} \
            --batch-import \
            --timeout ${import_timeout} \
            --output "${docker_storage}" \
            --verbose \
            -- ${docker_containers}

        if [ $? -ne 0 ]; then
            bbfatal "Docker container import failed"
        fi

        if [ -f "${docker_storage}" ]; then
            mkdir -p "${IMAGE_ROOTFS}/var/lib"
            bbnote "Extracting Docker storage to rootfs..."
            if ! tar -xf "${docker_storage}" -C "${IMAGE_ROOTFS}/var/lib" --no-same-owner; then
                bbwarn "Docker storage extraction failed, trying with verbose..."
                tar -xvf "${docker_storage}" -C "${IMAGE_ROOTFS}/var/lib" --no-same-owner 2>&1 | head -50
            fi
            rm -f "${docker_storage}"
            bbnote "Docker storage extraction complete"
        fi
    fi

    # Import all Podman containers via vrunner (single invocation)
    if [ -n "${podman_containers}" ]; then
        bbnote "Importing Podman containers via vrunner: ${podman_containers}"

        local podman_storage="${WORKDIR}/podman-storage-$$.tar"

        # Calculate timeout: base startup + per-container time
        local num_containers=$(echo "${podman_containers}" | wc -w)
        local import_timeout=$(expr ${CONTAINER_IMPORT_TIMEOUT_BASE} + $num_containers \* ${CONTAINER_IMPORT_TIMEOUT_PER})
        bbnote "Podman batch import timeout: ${import_timeout}s (${num_containers} containers)"

        ${VRUNNER_PATH} \
            --no-daemon \
            --runtime podman \
            --arch ${BLOB_ARCH} \
            --blob-dir ${VPDMN_BLOB_DIR} \
            --batch-import \
            --timeout ${import_timeout} \
            --output "${podman_storage}" \
            --verbose \
            -- ${podman_containers}

        if [ $? -ne 0 ]; then
            bbfatal "Podman container import failed"
        fi

        if [ -f "${podman_storage}" ]; then
            mkdir -p "${IMAGE_ROOTFS}/var/lib/containers/storage"
            bbnote "Extracting Podman storage to rootfs..."
            if ! tar -xf "${podman_storage}" -C "${IMAGE_ROOTFS}/var/lib/containers/storage" --no-same-owner; then
                bbwarn "Podman storage extraction failed, trying with verbose..."
                tar -xvf "${podman_storage}" -C "${IMAGE_ROOTFS}/var/lib/containers/storage" --no-same-owner 2>&1 | head -50
            fi
            rm -f "${podman_storage}"
            bbnote "Podman storage extraction complete"
        fi
    fi

    # Process autostart metadata from bundle packages
    for meta in ${BUNDLES_DIR}/*.meta; do
        [ -f "$meta" ] || continue
        bbnote "Processing autostart metadata: $(basename $meta)"

        while IFS= read -r bundle || [ -n "$bundle" ]; do
            [ -z "$bundle" ] && continue

            # Parse: source:runtime[:autostart-policy]
            # source may contain colons (e.g., docker.io/library/busybox:1.36)
            # Parse from the end: extract autostart first, then runtime, rest is source
            local autostart_policy=""
            local runtime_type=""
            local source=""

            # Check if last field is an autostart policy
            local last_field=$(echo "$bundle" | rev | cut -d: -f1 | rev)
            case "$last_field" in
                autostart|always|unless-stopped|on-failure|no)
                    autostart_policy="$last_field"
                    # Get runtime (second to last) and source (rest)
                    local without_autostart=$(echo "$bundle" | sed "s/:${autostart_policy}$//")
                    runtime_type=$(echo "$without_autostart" | rev | cut -d: -f1 | rev)
                    source=$(echo "$without_autostart" | sed "s/:${runtime_type}$//")
                    ;;
                docker|podman)
                    # No autostart, last field is runtime
                    runtime_type="$last_field"
                    source=$(echo "$bundle" | sed "s/:${runtime_type}$//")
                    ;;
                *)
                    # Unexpected format, try simple parsing
                    source=$(echo "$bundle" | cut -d: -f1)
                    runtime_type=$(echo "$bundle" | cut -d: -f2)
                    autostart_policy=$(echo "$bundle" | cut -d: -f3)
                    ;;
            esac

            # Skip if no autostart requested
            [ -z "$autostart_policy" ] && continue

            # Normalize autostart policy
            local restart_policy
            case "$autostart_policy" in
                autostart|unless-stopped)
                    restart_policy="unless-stopped"
                    ;;
                always|on-failure|no)
                    restart_policy="$autostart_policy"
                    ;;
                *)
                    bbwarn "Unknown restart policy '$autostart_policy' for $source, using 'unless-stopped'"
                    restart_policy="unless-stopped"
                    ;;
            esac

            # Extract image name from source
            local image_name
            local image_tag="latest"
            if echo "$source" | grep -qE '[/.]'; then
                # Remote container URL
                image_name=$(echo "$source" | sed 's|.*/||' | sed 's/:.*$//')
                image_tag=$(echo "$source" | grep -oE ':[^:]+$' | sed 's/^://' || echo "latest")
            else
                # Local container name
                image_name="$source"
                image_tag="latest"
            fi

            local service_name="container-$(echo "$image_name" | sed 's/[^a-zA-Z0-9_-]/-/g' | tr '[:upper:]' '[:lower:]')"

            bbnote "Creating autostart service for $source ($runtime_type, restart=$restart_policy)"

            # Check for custom service file in bundle's services directory
            # Custom files are stored as: services/<source-sanitized>.(service|container)
            local source_sanitized=$(echo "$source" | sed 's|[/:]|_|g')
            local custom_service_file=""

            if [ "$runtime_type" = "docker" ]; then
                custom_service_file="${BUNDLES_DIR}/${runtime_type}/services/${source_sanitized}.service"
            elif [ "$runtime_type" = "podman" ]; then
                custom_service_file="${BUNDLES_DIR}/${runtime_type}/services/${source_sanitized}.container"
            fi

            if [ -n "$custom_service_file" ] && [ -f "$custom_service_file" ]; then
                bbnote "Using custom service file from bundle: $custom_service_file"
                install_custom_service_from_bundle "$source" "$service_name" "$runtime_type" "$custom_service_file"
            elif [ "$runtime_type" = "docker" ]; then
                generate_docker_service_from_bundle "$service_name" "$image_name" "$image_tag" "$restart_policy"
            elif [ "$runtime_type" = "podman" ]; then
                generate_podman_service_from_bundle "$service_name" "$image_name" "$image_tag" "$restart_policy"
            fi
        done < "$meta"
    done

    # Clean up bundle files from final image (they're just intermediate artifacts)
    rm -rf "${BUNDLES_DIR}"
    bbnote "Cleaned up container bundle files"

    return 0
}

# Install a custom service file from a bundle package
# Args: source service_name runtime_type custom_file
install_custom_service_from_bundle() {
    local source="$1"
    local service_name="$2"
    local runtime_type="$3"
    local custom_file="$4"

    if [ ! -f "$custom_file" ]; then
        bbwarn "Custom service file not found: $custom_file (for container $source)"
        return 1
    fi

    if [ "$runtime_type" = "docker" ]; then
        # Docker: Install as systemd service
        local service_dir="${IMAGE_ROOTFS}/lib/systemd/system"
        local service_file="${service_dir}/${service_name}.service"

        mkdir -p "$service_dir"
        install -m 0644 "$custom_file" "$service_file"

        # Enable the service via symlink
        local wants_dir="${IMAGE_ROOTFS}/etc/systemd/system/multi-user.target.wants"
        mkdir -p "$wants_dir"
        ln -sf "/lib/systemd/system/${service_name}.service" "${wants_dir}/${service_name}.service"

        bbnote "Installed custom service from bundle: $custom_file -> ${service_name}.service"

    elif [ "$runtime_type" = "podman" ]; then
        # Podman: Install as Quadlet container file
        local quadlet_dir="${IMAGE_ROOTFS}/etc/containers/systemd"
        local container_file="${quadlet_dir}/${service_name}.container"

        mkdir -p "$quadlet_dir"
        install -m 0644 "$custom_file" "$container_file"

        bbnote "Installed custom Quadlet file from bundle: $custom_file -> ${service_name}.container"
    else
        bbwarn "Unknown runtime '$runtime_type' for custom service file from bundle, skipping"
        return 1
    fi

    return 0
}

# Generate Docker systemd service (for bundle packages)
generate_docker_service_from_bundle() {
    local service_name="$1"
    local image_name="$2"
    local image_tag="$3"
    local restart_policy="$4"

    local service_dir="${IMAGE_ROOTFS}/lib/systemd/system"
    local service_file="${service_dir}/${service_name}.service"

    mkdir -p "$service_dir"

    cat > "$service_file" << EOF
[Unit]
Description=Docker Container ${image_name}:${image_tag}
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=${restart_policy}
RestartSec=5s
TimeoutStartSec=0
ExecStartPre=-/usr/bin/docker rm -f ${image_name}
ExecStart=/usr/bin/docker run --rm --name ${image_name} ${image_name}:${image_tag}
ExecStop=/usr/bin/docker stop ${image_name}

[Install]
WantedBy=multi-user.target
EOF

    local wants_dir="${IMAGE_ROOTFS}/etc/systemd/system/multi-user.target.wants"
    mkdir -p "$wants_dir"
    ln -sf "/lib/systemd/system/${service_name}.service" "${wants_dir}/${service_name}.service"

    bbnote "Created and enabled ${service_name}.service for Docker container ${image_name}:${image_tag}"
}

# Generate Podman Quadlet container file (for bundle packages)
generate_podman_service_from_bundle() {
    local service_name="$1"
    local image_name="$2"
    local image_tag="$3"
    local restart_policy="$4"

    local quadlet_dir="${IMAGE_ROOTFS}/etc/containers/systemd"
    local container_file="${quadlet_dir}/${service_name}.container"

    mkdir -p "$quadlet_dir"

    cat > "$container_file" << EOF
# Quadlet container file for ${image_name}:${image_tag}
# Generated by container-cross-install

[Unit]
Description=Podman Container ${image_name}:${image_tag}

[Container]
Image=${image_name}:${image_tag}
ContainerName=${image_name}

[Service]
Restart=${restart_policy}
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    bbnote "Created Quadlet file ${service_name}.container for Podman container ${image_name}:${image_tag}"
}

bundle_containers() {
    set +e

    # ========================================================================
    # Helper functions for autostart support
    # These must be defined INSIDE bundle_containers() to be available in
    # bitbake's ROOTFS_POSTPROCESS_COMMAND execution context
    # ========================================================================

    # Extract container image name and tag from OCI directory name
    # Sets: CONTAINER_IMAGE_NAME, CONTAINER_IMAGE_TAG
    # Input: /path/to/container-base-latest-oci or /path/to/app-container-multilayer-latest-oci
    # Output: container-base:latest or app-container-multilayer:latest
    # Note: Use _cci_ prefix to avoid conflicts with bitbake's environment variables
    extract_container_info() {
        _cci_oci_path="$1"
        _cci_dir_name=$(basename "$_cci_oci_path" | sed 's/-oci$//')

        CONTAINER_IMAGE_NAME=""
        CONTAINER_IMAGE_TAG="latest"

        # Check if name ends with -latest or a version tag (-X.Y, -X.Y.Z, -vX.Y, etc.)
        # The last hyphen-separated part is the tag if it looks like a version or is "latest"
        _cci_last_part=$(echo "$_cci_dir_name" | rev | cut -d- -f1 | rev)

        # Check if last part is a tag (latest, or version-like: 1.0, v1.0, 1.0.0, etc.)
        if echo "$_cci_last_part" | grep -qE '^(latest|v?[0-9]+\.[0-9]+(\.[0-9]+)?|[0-9]+)$'; then
            # Strip the tag from the end to get the image name
            CONTAINER_IMAGE_TAG="$_cci_last_part"
            CONTAINER_IMAGE_NAME=$(echo "$_cci_dir_name" | sed "s/-${_cci_last_part}$//")
        else
            # No recognizable tag suffix, use whole name with default tag
            CONTAINER_IMAGE_NAME="$_cci_dir_name"
            CONTAINER_IMAGE_TAG="latest"
        fi
    }

    # Resolve OCI directory - support both recipe names and OCI dir names
    # Input: container name (e.g., "container-base" or "container-base-latest-oci")
    # Output: full path to OCI directory, or empty string if not found
    resolve_oci_dir() {
        local name="$1"
        # If already ends in -oci, use as-is
        if echo "$name" | grep -q '\-oci$'; then
            echo "${DEPLOY_DIR_IMAGE}/${name}"
            return
        fi
        # Fallback search (same as container-bundle.bbclass)
        if [ -d "${DEPLOY_DIR_IMAGE}/${name}-latest-oci" ]; then
            echo "${DEPLOY_DIR_IMAGE}/${name}-latest-oci"
        elif [ -d "${DEPLOY_DIR_IMAGE}/${name}-oci" ]; then
            echo "${DEPLOY_DIR_IMAGE}/${name}-oci"
        else
            echo ""
        fi
    }

    # Convert container name to valid systemd service name
    # Input: my-app/special:latest
    # Output: my-app-special-latest
    sanitize_service_name() {
        local name="$1"
        echo "$name" | sed 's/[^a-zA-Z0-9_-]/-/g' | tr '[:upper:]' '[:lower:]'
    }

    # Generate Docker systemd service file
    # Args: service_name image_name image_tag restart_policy
    generate_docker_service() {
        local service_name="$1"
        local image_name="$2"
        local image_tag="$3"
        local restart_policy="$4"

        # Use standard paths - systemd_system_unitdir is /lib/systemd/system
        local service_dir="${IMAGE_ROOTFS}/lib/systemd/system"
        local service_file="${service_dir}/${service_name}.service"

        mkdir -p "$service_dir"

        cat > "$service_file" << EOF
[Unit]
Description=Docker Container ${image_name}:${image_tag}
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=${restart_policy}
RestartSec=5s
TimeoutStartSec=0
ExecStartPre=-/usr/bin/docker rm -f ${image_name}
ExecStart=/usr/bin/docker run --rm --name ${image_name} ${image_name}:${image_tag}
ExecStop=/usr/bin/docker stop ${image_name}

[Install]
WantedBy=multi-user.target
EOF

        # Enable the service via symlink
        local wants_dir="${IMAGE_ROOTFS}/etc/systemd/system/multi-user.target.wants"
        mkdir -p "$wants_dir"
        ln -sf "/lib/systemd/system/${service_name}.service" "${wants_dir}/${service_name}.service"

        bbnote "Created and enabled ${service_name}.service for Docker container ${image_name}:${image_tag}"
    }

    # Generate Podman Quadlet container file
    # Args: service_name image_name image_tag restart_policy
    generate_podman_service() {
        local service_name="$1"
        local image_name="$2"
        local image_tag="$3"
        local restart_policy="$4"

        # Use Quadlet format for modern Podman
        local quadlet_dir="${IMAGE_ROOTFS}/etc/containers/systemd"
        local container_file="${quadlet_dir}/${service_name}.container"

        mkdir -p "$quadlet_dir"

        cat > "$container_file" << EOF
# Quadlet container file for ${image_name}:${image_tag}
# Generated by container-cross-install

[Unit]
Description=Podman Container ${image_name}:${image_tag}

[Container]
Image=${image_name}:${image_tag}
ContainerName=${image_name}

[Service]
Restart=${restart_policy}
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

        bbnote "Created Quadlet file ${service_name}.container for Podman container ${image_name}:${image_tag}"
    }

    # Install a custom service file provided by the user
    # Args: container_name service_name runtime_type custom_file
    install_custom_service() {
        local container_name="$1"
        local service_name="$2"
        local runtime_type="$3"
        local custom_file="$4"

        if [ ! -f "$custom_file" ]; then
            bbfatal "Custom service file not found: $custom_file (for container $container_name)"
        fi

        if [ "$runtime_type" = "docker" ]; then
            # Docker: Install as systemd service
            local service_dir="${IMAGE_ROOTFS}/lib/systemd/system"
            local service_file="${service_dir}/${service_name}.service"

            mkdir -p "$service_dir"
            install -m 0644 "$custom_file" "$service_file"

            # Enable the service via symlink
            local wants_dir="${IMAGE_ROOTFS}/etc/systemd/system/multi-user.target.wants"
            mkdir -p "$wants_dir"
            ln -sf "/lib/systemd/system/${service_name}.service" "${wants_dir}/${service_name}.service"

            bbnote "Installed custom service: $custom_file -> ${service_name}.service"

        elif [ "$runtime_type" = "podman" ]; then
            # Podman: Install as Quadlet container file
            local quadlet_dir="${IMAGE_ROOTFS}/etc/containers/systemd"
            local container_file="${quadlet_dir}/${service_name}.container"

            mkdir -p "$quadlet_dir"
            install -m 0644 "$custom_file" "$container_file"

            bbnote "Installed custom Quadlet file: $custom_file -> ${service_name}.container"
        else
            bbwarn "Unknown runtime '$runtime_type' for custom service file, skipping"
        fi
    }

    # Install autostart services for containers with autostart policy
    install_autostart_services() {
        bbnote "Processing container autostart services..."

        if [ -z "${BUNDLED_CONTAINERS}" ]; then
            return 0
        fi

        for bc in ${BUNDLED_CONTAINERS}; do
            # Parse extended format: container:runtime[:autostart-policy]
            local container_name="$(echo $bc | cut -d: -f1)"
            local runtime_type="$(echo $bc | cut -d: -f2)"
            local autostart_policy="$(echo $bc | cut -d: -f3)"

            # Default runtime from CONTAINER_PROFILE if not specified
            if [ "$container_name" = "$runtime_type" ]; then
                runtime_type="${CONTAINER_DEFAULT_RUNTIME}"
                autostart_policy=""
            fi

            # Skip if no autostart requested
            if [ -z "$autostart_policy" ]; then
                bbnote "Container $container_name: no autostart configured"
                continue
            fi

            # Normalize autostart policy
            local restart_policy
            case "$autostart_policy" in
                autostart|unless-stopped)
                    restart_policy="unless-stopped"
                    ;;
                always|on-failure|no)
                    restart_policy="$autostart_policy"
                    ;;
                *)
                    bbwarn "Unknown restart policy '$autostart_policy' for $container_name, using 'unless-stopped'"
                    restart_policy="unless-stopped"
                    ;;
            esac

            # Extract image name and tag from OCI directory
            extract_container_info "${DEPLOY_DIR_IMAGE}/$container_name"

            # Generate service name
            local service_name="container-$(sanitize_service_name "${CONTAINER_IMAGE_NAME}")"

            bbnote "Creating autostart service for $container_name ($runtime_type, restart=$restart_policy)"

            # Check for custom service file via CONTAINER_SERVICE_FILE varflag
            # This is evaluated at rootfs time, so we use a Python helper
            local custom_service_file="${CONTAINER_SERVICE_FILE_MAP}"
            local custom_file=""

            # Parse the map to find this container's custom file
            # Format: container1=/path/to/file1;container2=/path/to/file2
            if [ -n "$custom_service_file" ]; then
                custom_file=$(echo "$custom_service_file" | tr ';' '\n' | grep "^${container_name}=" | cut -d= -f2-)
            fi

            if [ -n "$custom_file" ] && [ -f "$custom_file" ]; then
                bbnote "Using custom service file for $container_name: $custom_file"
                install_custom_service "$container_name" "$service_name" "$runtime_type" "$custom_file"
            elif [ "$runtime_type" = "docker" ]; then
                generate_docker_service "$service_name" "${CONTAINER_IMAGE_NAME}" "${CONTAINER_IMAGE_TAG}" "$restart_policy"
            elif [ "$runtime_type" = "podman" ]; then
                generate_podman_service "$service_name" "${CONTAINER_IMAGE_NAME}" "${CONTAINER_IMAGE_TAG}" "$restart_policy"
            else
                bbwarn "Unknown runtime '$runtime_type' for autostart, skipping service generation"
            fi
        done
    }

    # ========================================================================
    # End helper functions
    # ========================================================================

    if [ -z "${BUNDLED_CONTAINERS}" ]; then
        bbnote "No bundled containers specified"
        return 0
    fi

    bbnote "Processing bundled containers: ${BUNDLED_CONTAINERS}"
    bbnote "Target architecture: ${QEMU_ARCH} (blob arch: ${BLOB_ARCH})"

    # Locate vrunner from vcontainer-native
    VRUNNER="${VRUNNER_PATH}"
    bbnote "vrunner: ${VRUNNER}"

    # Verify vrunner exists
    if [ ! -f "${VRUNNER}" ]; then
        bbfatal "vrunner not found at ${VRUNNER}. Ensure vcontainer-native is built."
    fi

    # ========================================================================
    # Collect containers by runtime for batch processing
    # Format: path:image:tag (as expected by vrunner --batch-import)
    # ========================================================================
    DOCKER_CONTAINERS=""
    PODMAN_CONTAINERS=""

    for bc in ${BUNDLED_CONTAINERS}; do
        # Strip :external tag if present (used for third-party blobs)
        # The :external tag only affects dependency generation (in __anonymous)
        bc_clean="$bc"
        if echo "$bc" | grep -q ':external'; then
            bc_clean=$(echo "$bc" | sed 's/:external//')
        fi

        container_name="$(echo $bc_clean | cut -d: -f1)"
        runtime_type="$(echo $bc_clean | cut -d: -f2)"

        # Default runtime from CONTAINER_PROFILE if not specified
        if [ "$container_name" = "$runtime_type" ]; then
            runtime_type="${CONTAINER_DEFAULT_RUNTIME}"
        fi

        bbnote "Collecting container: $container_name (runtime: $runtime_type)"

        # Resolve OCI directory (supports both recipe names and OCI dir names)
        oci_dir=$(resolve_oci_dir "$container_name")
        if [ -z "$oci_dir" ] || [ ! -e "$oci_dir" ]; then
            bbfatal "============================================================
MISSING CONTAINER: $container_name
============================================================
OCI directory not found for '$container_name'

Searched for:
  ${DEPLOY_DIR_IMAGE}/${container_name}-latest-oci
  ${DEPLOY_DIR_IMAGE}/${container_name}-oci
  ${DEPLOY_DIR_IMAGE}/${container_name}

To fix, build the container for this machine:
  MACHINE=${MACHINE} bitbake ${container_name}

Or remove it from BUNDLED_CONTAINERS if not needed.
============================================================"
        fi

        # Extract image name and tag from OCI directory name
        extract_container_info "$oci_dir"
        BATCH_ENTRY="${oci_dir}:${CONTAINER_IMAGE_NAME}:${CONTAINER_IMAGE_TAG}"

        if [ "$runtime_type" = "docker" ]; then
            DOCKER_CONTAINERS="${DOCKER_CONTAINERS} ${BATCH_ENTRY}"
        elif [ "$runtime_type" = "podman" ]; then
            PODMAN_CONTAINERS="${PODMAN_CONTAINERS} ${BATCH_ENTRY}"
        else
            bbwarn "Unknown runtime type: $runtime_type for $container_name, skipping"
        fi
    done

    # ========================================================================
    # Process Docker containers (batch import)
    # ========================================================================
    if [ -n "${DOCKER_CONTAINERS}" ]; then
        bbnote "Processing Docker containers: ${DOCKER_CONTAINERS}"

        DOCKER_STORAGE_TAR="${WORKDIR}/docker-storage-$$.tar"
        DOCKER_OUTPUT_DIR="${IMAGE_ROOTFS}/var/lib/docker"

        # Verify Docker blobs exist
        if [ ! -d "${VDKR_BLOB_DIR}" ]; then
            bbfatal "Docker blob directory not found at ${VDKR_BLOB_DIR}. Build with: bitbake vdkr-initramfs-create"
        fi

        # Check for existing Docker storage in rootfs (additive support)
        EXISTING_DOCKER_STORAGE=""
        if [ -d "${DOCKER_OUTPUT_DIR}" ] && [ -n "$(ls -A ${DOCKER_OUTPUT_DIR} 2>/dev/null)" ]; then
            bbnote "Found existing Docker storage, will merge additively"
            EXISTING_DOCKER_STORAGE="${WORKDIR}/existing-docker-$$.tar"
            tar -cf "${EXISTING_DOCKER_STORAGE}" -C "${IMAGE_ROOTFS}/var/lib" docker
        fi

        # Calculate timeout: base startup + per-container time
        NUM_DOCKER=$(echo "${DOCKER_CONTAINERS}" | wc -w)
        DOCKER_TIMEOUT=$(expr ${CONTAINER_IMPORT_TIMEOUT_BASE} + $NUM_DOCKER \* ${CONTAINER_IMPORT_TIMEOUT_PER})
        bbnote "Docker batch import timeout: ${DOCKER_TIMEOUT}s (${NUM_DOCKER} containers)"

        # Build vrunner batch-import command
        VRUNNER_CMD="${VRUNNER} \
            --runtime docker \
            --arch ${BLOB_ARCH} \
            --blob-dir ${VDKR_BLOB_DIR} \
            --batch-import \
            --timeout ${DOCKER_TIMEOUT} \
            --output ${DOCKER_STORAGE_TAR} \
            --verbose"

        if [ -n "${EXISTING_DOCKER_STORAGE}" ]; then
            VRUNNER_CMD="${VRUNNER_CMD} --input-storage ${EXISTING_DOCKER_STORAGE}"
        fi

        VRUNNER_CMD="${VRUNNER_CMD} -- ${DOCKER_CONTAINERS}"

        bbnote "Running batch import for Docker containers..."
        # Prepend native sysroot to PATH so vrunner finds the correct QEMU (with virtfs support)
        PATH="${STAGING_BINDIR_NATIVE}:${PATH}" TMPDIR="${WORKDIR}" eval ${VRUNNER_CMD}

        if [ $? -ne 0 ]; then
            bbfatal "Docker batch import failed"
        fi

        # Simple tar extraction - no merger needed!
        # The storage tar has correct structure with docker/ at root
        if [ -f "${DOCKER_STORAGE_TAR}" ]; then
            bbnote "Extracting Docker storage to rootfs..."
            mkdir -p "${DOCKER_OUTPUT_DIR}"
            # Extract with --strip-components=1 to remove the 'docker' prefix
            # since we're extracting directly into /var/lib/docker
            tar -xf "${DOCKER_STORAGE_TAR}" -C "${IMAGE_ROOTFS}/var/lib" --no-same-owner
            bbnote "Docker storage extracted successfully"
        fi

        rm -f "${EXISTING_DOCKER_STORAGE}"
    fi

    # ========================================================================
    # Process Podman containers (batch import)
    # ========================================================================
    if [ -n "${PODMAN_CONTAINERS}" ]; then
        bbnote "Processing Podman containers: ${PODMAN_CONTAINERS}"

        PODMAN_STORAGE_TAR="${WORKDIR}/podman-storage-$$.tar"
        PODMAN_OUTPUT_DIR="${IMAGE_ROOTFS}/var/lib/containers/storage"

        # Verify Podman blobs exist
        if [ ! -d "${VPDMN_BLOB_DIR}" ]; then
            bbfatal "Podman blob directory not found at ${VPDMN_BLOB_DIR}. Build with: bitbake vpdmn-initramfs-create"
        fi

        # Check for existing Podman storage in rootfs (additive support)
        EXISTING_PODMAN_STORAGE=""
        if [ -d "${PODMAN_OUTPUT_DIR}" ] && [ -n "$(ls -A ${PODMAN_OUTPUT_DIR} 2>/dev/null)" ]; then
            bbnote "Found existing Podman storage, will merge additively"
            EXISTING_PODMAN_STORAGE="${WORKDIR}/existing-podman-$$.tar"
            tar -cf "${EXISTING_PODMAN_STORAGE}" -C "${IMAGE_ROOTFS}/var/lib/containers" storage
        fi

        # Calculate timeout: base startup + per-container time
        NUM_PODMAN=$(echo "${PODMAN_CONTAINERS}" | wc -w)
        PODMAN_TIMEOUT=$(expr ${CONTAINER_IMPORT_TIMEOUT_BASE} + $NUM_PODMAN \* ${CONTAINER_IMPORT_TIMEOUT_PER})
        bbnote "Podman batch import timeout: ${PODMAN_TIMEOUT}s (${NUM_PODMAN} containers)"

        # Build vrunner batch-import command
        VRUNNER_CMD="${VRUNNER} \
            --runtime podman \
            --arch ${BLOB_ARCH} \
            --blob-dir ${VPDMN_BLOB_DIR} \
            --batch-import \
            --timeout ${PODMAN_TIMEOUT} \
            --output ${PODMAN_STORAGE_TAR} \
            --verbose"

        if [ -n "${EXISTING_PODMAN_STORAGE}" ]; then
            VRUNNER_CMD="${VRUNNER_CMD} --input-storage ${EXISTING_PODMAN_STORAGE}"
        fi

        VRUNNER_CMD="${VRUNNER_CMD} -- ${PODMAN_CONTAINERS}"

        bbnote "Running batch import for Podman containers..."
        # Prepend native sysroot to PATH so vrunner finds the correct QEMU (with virtfs support)
        PATH="${STAGING_BINDIR_NATIVE}:${PATH}" TMPDIR="${WORKDIR}" eval ${VRUNNER_CMD}

        if [ $? -ne 0 ]; then
            bbfatal "Podman batch import failed"
        fi

        # Simple tar extraction - no merger needed!
        if [ -f "${PODMAN_STORAGE_TAR}" ]; then
            bbnote "Extracting Podman storage to rootfs..."
            mkdir -p "${PODMAN_OUTPUT_DIR}"
            tar -xf "${PODMAN_STORAGE_TAR}" -C "${PODMAN_OUTPUT_DIR}" --no-same-owner
            bbnote "Podman storage extracted successfully"
        fi

        rm -f "${EXISTING_PODMAN_STORAGE}"
    fi

    # ========================================================================
    # Install autostart services
    # ========================================================================
    install_autostart_services

    bbnote "Done processing all bundled containers"
}

# First merge any bundles installed via IMAGE_INSTALL, then process BUNDLED_CONTAINERS
ROOTFS_POSTPROCESS_COMMAND += "merge_installed_bundles; bundle_containers;"
