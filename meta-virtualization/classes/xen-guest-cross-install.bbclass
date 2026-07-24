# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# xen-guest-cross-install.bbclass
# ===========================================================================
# Xen guest bundling class for Dom0 images
# ===========================================================================
#
# This class enables bundling Xen guest images into a Dom0 host image during
# build time. It follows the same pattern as container-cross-install.bbclass:
# variable-driven, parse-time dependency generation, and a structured
# ROOTFS_POSTPROCESS_COMMAND.
#
# Usage (in image recipe):
#   inherit xen-guest-cross-install
#
# Configuration (in local.conf or image recipe):
#   BUNDLED_XEN_GUESTS = "xen-guest-image-minimal"
#   BUNDLED_XEN_GUESTS = "xen-guest-image-minimal:autostart"
#   BUNDLED_XEN_GUESTS = "xen-guest-image-minimal my-other-guest:autostart"
#   BUNDLED_XEN_GUESTS = "prebuilt-guest:external"
#
# Guest format: recipe-name[:autostart][:external]
#   - recipe-name: Yocto image recipe name that produces the guest rootfs
#   - autostart: Optional. Creates symlink in /etc/xen/auto/ for xendomains
#   - external: Optional. Skip dependency generation (3rd-party guest)
#
# Per-guest configuration via varflags:
#   XEN_GUEST_MEMORY[guest-name] = "1024"
#   XEN_GUEST_VCPUS[guest-name] = "2"
#   XEN_GUEST_VIF[guest-name] = "bridge=xenbr0"
#   XEN_GUEST_EXTRA[guest-name] = "root=/dev/xvda ro console=hvc0 ip=dhcp"
#   XEN_GUEST_DISK_DEVICE[guest-name] = "xvda"
#   XEN_GUEST_NAME[guest-name] = "my-custom-name"
#
# Custom config file (replaces auto-generation entirely):
#   XEN_GUEST_CONFIG_FILE[guest-name] = "${UNPACKDIR}/custom.cfg"
#
# Explicit rootfs/kernel paths (for external/3rd-party guests):
#   XEN_GUEST_ROOTFS[my-vendor-guest] = "vendor-rootfs.ext4"
#   XEN_GUEST_KERNEL[my-vendor-guest] = "vendor-kernel"
#
# Artifacts installed on target:
#   /var/lib/xen/images/  - guest rootfs and kernel files
#   /etc/xen/<guest>.cfg  - Xen guest configuration files
#   /etc/xen/auto/        - symlinks for autostart guests (xendomains)
#
# Guests can be launched after boot with:
#   xl create -c /etc/xen/<guest>.cfg
#

# ===========================================================================
# Default variables
# ===========================================================================

BUNDLED_XEN_GUESTS ?= ""
XEN_GUEST_IMAGE_FSTYPE ?= "ext4"
XEN_GUEST_MEMORY_DEFAULT ?= "512"
XEN_GUEST_VCPUS_DEFAULT ?= "1"
XEN_GUEST_VIF_DEFAULT ?= "bridge=xenbr0"
XEN_GUEST_EXTRA_DEFAULT ?= "root=/dev/xvda ro ip=dhcp"
XEN_GUEST_DISK_DEVICE_DEFAULT ?= "xvda"

# ===========================================================================
# Parse-time dependency generation
# ===========================================================================

python __anonymous() {
    bundled = (d.getVar('BUNDLED_XEN_GUESTS') or "").split()
    if not bundled:
        return

    deps = ""
    for entry in bundled:
        parts = entry.split(':')
        guest_name = parts[0]

        # Check for :external tag
        is_external = 'external' in parts

        # Skip dependency for external guests
        if is_external:
            continue

        # Generate dependency on guest recipe
        deps += " %s:do_image_complete" % guest_name

    if deps:
        d.appendVarFlag('do_rootfs', 'depends', deps)
}

# ===========================================================================
# Python helpers - build varflag maps for shell access
# ===========================================================================

# Build XEN_GUEST_CONFIG_FILE_MAP from varflags
# Format: guest1=/path/to/file1;guest2=/path/to/file2
def get_xen_guest_config_map(d):
    bundled = (d.getVar('BUNDLED_XEN_GUESTS') or "").split()
    if not bundled:
        return ""

    mappings = []
    for entry in bundled:
        parts = entry.split(':')
        guest_name = parts[0]
        custom_file = d.getVarFlag('XEN_GUEST_CONFIG_FILE', guest_name)
        if custom_file:
            mappings.append("%s=%s" % (guest_name, custom_file))

    return ";".join(mappings)

XEN_GUEST_CONFIG_FILE_MAP = "${@get_xen_guest_config_map(d)}"

# Build XEN_GUEST_PARAMS_MAP from varflags
# Format: guest1=memory|vcpus|vif|extra|disk_device|name|rootfs|kernel;guest2=...
def get_xen_guest_params(d):
    bundled = (d.getVar('BUNDLED_XEN_GUESTS') or "").split()
    if not bundled:
        return ""

    mem_default = d.getVar('XEN_GUEST_MEMORY_DEFAULT')
    vcpus_default = d.getVar('XEN_GUEST_VCPUS_DEFAULT')
    vif_default = d.getVar('XEN_GUEST_VIF_DEFAULT')
    extra_default = d.getVar('XEN_GUEST_EXTRA_DEFAULT')
    disk_default = d.getVar('XEN_GUEST_DISK_DEVICE_DEFAULT')

    mappings = []
    for entry in bundled:
        parts = entry.split(':')
        guest_name = parts[0]

        memory = d.getVarFlag('XEN_GUEST_MEMORY', guest_name) or mem_default
        vcpus = d.getVarFlag('XEN_GUEST_VCPUS', guest_name) or vcpus_default
        vif = d.getVarFlag('XEN_GUEST_VIF', guest_name) or vif_default
        extra = d.getVarFlag('XEN_GUEST_EXTRA', guest_name) or extra_default
        disk_device = d.getVarFlag('XEN_GUEST_DISK_DEVICE', guest_name) or disk_default
        name = d.getVarFlag('XEN_GUEST_NAME', guest_name) or guest_name
        rootfs = d.getVarFlag('XEN_GUEST_ROOTFS', guest_name) or ""
        kernel = d.getVarFlag('XEN_GUEST_KERNEL', guest_name) or ""

        params = "|".join([memory, vcpus, vif, extra, disk_device, name, rootfs, kernel])
        mappings.append("%s=%s" % (guest_name, params))

    return ";".join(mappings)

XEN_GUEST_PARAMS_MAP = "${@get_xen_guest_params(d)}"

# ===========================================================================
# Shell function: merge_installed_xen_bundles
# Processes packages created by xen-guest-bundle.bbclass
# ===========================================================================

merge_installed_xen_bundles() {
    set +e

    BUNDLES_DIR="${IMAGE_ROOTFS}${datadir}/xen-guest-bundles"

    if [ ! -d "${BUNDLES_DIR}" ]; then
        bbnote "No Xen guest bundles found in ${BUNDLES_DIR}"
        return 0
    fi

    bbnote "Processing installed Xen guest bundles from ${BUNDLES_DIR}"

    DEST_DIR="${IMAGE_ROOTFS}/var/lib/xen/images"
    CONFIG_DIR="${IMAGE_ROOTFS}/etc/xen"
    AUTO_DIR="${IMAGE_ROOTFS}/etc/xen/auto"

    mkdir -p "$DEST_DIR"
    mkdir -p "$CONFIG_DIR"

    for bundle_dir in ${BUNDLES_DIR}/*/; do
        [ -d "$bundle_dir" ] || continue

        manifest="${bundle_dir}manifest"
        if [ ! -f "$manifest" ]; then
            bbwarn "No manifest found in $bundle_dir, skipping"
            continue
        fi

        bundle_name=$(basename "$bundle_dir")
        bbnote "Processing bundle: $bundle_name"

        while IFS=: read -r guest_name rootfs_file kernel_file autostart_flag || [ -n "$guest_name" ]; do
            [ -z "$guest_name" ] && continue

            bbnote "  Guest: $guest_name (rootfs=$rootfs_file kernel=$kernel_file autostart=$autostart_flag)"

            # Copy rootfs
            if [ -f "${bundle_dir}images/${rootfs_file}" ]; then
                cp "${bundle_dir}images/${rootfs_file}" "$DEST_DIR/"
                bbnote "  Installed rootfs: $rootfs_file"
            else
                bbwarn "  Rootfs not found: ${bundle_dir}images/${rootfs_file}"
            fi

            # Copy kernel
            if [ -f "${bundle_dir}images/${kernel_file}" ]; then
                cp "${bundle_dir}images/${kernel_file}" "$DEST_DIR/"
                bbnote "  Installed kernel: $kernel_file"
            else
                bbwarn "  Kernel not found: ${bundle_dir}images/${kernel_file}"
            fi

            # Copy config
            if [ -f "${bundle_dir}configs/${guest_name}.cfg" ]; then
                cp "${bundle_dir}configs/${guest_name}.cfg" "${CONFIG_DIR}/"
                bbnote "  Installed config: ${guest_name}.cfg"
            else
                bbwarn "  Config not found: ${bundle_dir}configs/${guest_name}.cfg"
            fi

            # Handle autostart
            if [ "$autostart_flag" = "autostart" ]; then
                mkdir -p "$AUTO_DIR"
                ln -sf "/etc/xen/${guest_name}.cfg" "${AUTO_DIR}/${guest_name}.cfg"
                bbnote "  Autostart enabled: ${guest_name}.cfg"
            fi

            bbnote "  Guest '$guest_name' merged successfully"
        done < "$manifest"
    done

    # Clean up bundle files from final image
    rm -rf "${BUNDLES_DIR}"
    bbnote "Cleaned up Xen guest bundle files"

    return 0
}

# ===========================================================================
# Shell function: bundle_xen_guests
# ROOTFS_POSTPROCESS_COMMAND
# ===========================================================================

bundle_xen_guests() {
    set +e

    # ========================================================================
    # Helper functions
    # Defined inside bundle_xen_guests() for bitbake execution context
    # ========================================================================

    # Extract a per-guest parameter from the params map
    # Args: guest_name field_index (0=memory, 1=vcpus, 2=vif, 3=extra,
    #        4=disk_device, 5=name, 6=rootfs_override, 7=kernel_override)
    get_guest_param() {
        local guest="$1"
        local field="$2"
        local params_map="${XEN_GUEST_PARAMS_MAP}"

        # Find this guest's params in the map
        local guest_params=$(echo "$params_map" | tr ';' '\n' | grep "^${guest}=" | cut -d= -f2-)
        if [ -z "$guest_params" ]; then
            return 1
        fi

        # Extract field by index (pipe-separated)
        echo "$guest_params" | cut -d'|' -f$(expr $field + 1)
    }

    # Resolve guest rootfs path
    # Checks varflag override first, then standard Yocto naming
    resolve_guest_rootfs() {
        local guest="$1"
        local override=$(get_guest_param "$guest" 6)

        if [ -n "$override" ]; then
            # Explicit rootfs filename provided
            local path="${DEPLOY_DIR_IMAGE}/$override"
            if [ -e "$path" ]; then
                readlink -f "$path"
                return 0
            fi
            bbwarn "XEN_GUEST_ROOTFS override '$override' not found at $path"
            return 1
        fi

        # Standard Yocto naming: <recipe>-<MACHINE>.<fstype>
        local path="${DEPLOY_DIR_IMAGE}/${guest}-${MACHINE}.${XEN_GUEST_IMAGE_FSTYPE}"
        if [ -e "$path" ]; then
            readlink -f "$path"
            return 0
        fi

        # Fallback: <recipe>-<MACHINE>.rootfs.<fstype>
        path="${DEPLOY_DIR_IMAGE}/${guest}-${MACHINE}.rootfs.${XEN_GUEST_IMAGE_FSTYPE}"
        if [ -e "$path" ]; then
            readlink -f "$path"
            return 0
        fi

        bbwarn "Guest rootfs not found for '$guest'. Searched:"
        bbwarn "  ${DEPLOY_DIR_IMAGE}/${guest}-${MACHINE}.${XEN_GUEST_IMAGE_FSTYPE}"
        bbwarn "  ${DEPLOY_DIR_IMAGE}/${guest}-${MACHINE}.rootfs.${XEN_GUEST_IMAGE_FSTYPE}"
        return 1
    }

    # Resolve guest kernel path
    # Checks varflag override first, then uses KERNEL_IMAGETYPE
    resolve_guest_kernel() {
        local guest="$1"
        local override=$(get_guest_param "$guest" 7)

        if [ -n "$override" ]; then
            # Explicit kernel filename provided
            local path="${DEPLOY_DIR_IMAGE}/$override"
            if [ -e "$path" ]; then
                readlink -f "$path"
                return 0
            fi
            bbwarn "XEN_GUEST_KERNEL override '$override' not found at $path"
            return 1
        fi

        # Default: shared kernel (same MACHINE)
        local path="${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}"
        if [ -e "$path" ]; then
            readlink -f "$path"
            return 0
        fi

        bbwarn "Guest kernel not found at ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}"
        return 1
    }

    # Generate a Xen guest configuration file
    # Args: guest_name rootfs_path kernel_path
    generate_xen_guest_config() {
        local guest="$1"
        local rootfs_basename="$2"
        local kernel_basename="$3"
        local outfile="$4"

        local memory=$(get_guest_param "$guest" 0)
        local vcpus=$(get_guest_param "$guest" 1)
        local vif=$(get_guest_param "$guest" 2)
        local extra=$(get_guest_param "$guest" 3)
        local disk_device=$(get_guest_param "$guest" 4)
        local name=$(get_guest_param "$guest" 5)

        cat > "$outfile" << EOF
name = "$name"
memory = $memory
vcpus = $vcpus
disk = ['file:/var/lib/xen/images/$rootfs_basename,$disk_device,rw']
vif = ['$vif']
kernel = "/var/lib/xen/images/$kernel_basename"
extra = "$extra"
EOF
    }

    # ========================================================================
    # Main loop
    # ========================================================================

    if [ -z "${BUNDLED_XEN_GUESTS}" ]; then
        bbnote "No Xen bundled guests specified"
        return 0
    fi

    bbnote "Processing Xen bundled guests: ${BUNDLED_XEN_GUESTS}"

    DEST_DIR="${IMAGE_ROOTFS}/var/lib/xen/images"
    CONFIG_DIR="${IMAGE_ROOTFS}/etc/xen"
    AUTO_DIR="${IMAGE_ROOTFS}/etc/xen/auto"

    mkdir -p "$DEST_DIR"
    mkdir -p "$CONFIG_DIR"

    for entry in ${BUNDLED_XEN_GUESTS}; do
        # Parse: recipe-name[:autostart][:external]
        guest_name="$(echo $entry | cut -d: -f1)"

        # Check for tags
        autostart=""
        if echo "$entry" | grep -q ':autostart'; then
            autostart="1"
        fi

        bbnote "Processing guest: $guest_name (autostart=$autostart)"

        # Resolve rootfs
        rootfs_path=$(resolve_guest_rootfs "$guest_name")
        if [ $? -ne 0 ] || [ -z "$rootfs_path" ]; then
            bbfatal "Cannot resolve rootfs for guest '$guest_name'"
        fi
        rootfs_basename=$(basename "$rootfs_path")

        # Resolve kernel
        kernel_path=$(resolve_guest_kernel "$guest_name")
        if [ $? -ne 0 ] || [ -z "$kernel_path" ]; then
            bbfatal "Cannot resolve kernel for guest '$guest_name'"
        fi
        kernel_basename=$(basename "$kernel_path")

        # Copy rootfs and kernel to target
        bbnote "Copying rootfs: $rootfs_path -> $DEST_DIR/"
        cp "$rootfs_path" "$DEST_DIR/"

        bbnote "Copying kernel: $kernel_path -> $DEST_DIR/"
        cp "$kernel_path" "$DEST_DIR/"

        # Generate or install config file
        config_map="${XEN_GUEST_CONFIG_FILE_MAP}"
        custom_config=$(echo "$config_map" | tr ';' '\n' | grep "^${guest_name}=" | cut -d= -f2-)

        if [ -n "$custom_config" ] && [ -f "$custom_config" ]; then
            bbnote "Installing custom config: $custom_config"
            # Fix paths in custom config to point to /var/lib/xen/images/
            sed -E \
                -e "s#^(disk = \[)[^,]+#\1'file:/var/lib/xen/images/$rootfs_basename#" \
                -e "s#^(kernel = )\"[^\"]+\"#\1\"/var/lib/xen/images/$kernel_basename\"#" \
                "$custom_config" > "${CONFIG_DIR}/${guest_name}.cfg"
        else
            bbnote "Generating config for $guest_name"
            generate_xen_guest_config "$guest_name" "$rootfs_basename" "$kernel_basename" \
                "${CONFIG_DIR}/${guest_name}.cfg"
        fi

        # Handle autostart
        if [ -n "$autostart" ]; then
            mkdir -p "$AUTO_DIR"
            ln -sf "/etc/xen/${guest_name}.cfg" "${AUTO_DIR}/${guest_name}.cfg"
            bbnote "Autostart enabled: ${AUTO_DIR}/${guest_name}.cfg -> /etc/xen/${guest_name}.cfg"
        fi

        bbnote "Guest '$guest_name' bundled successfully"
    done

    bbnote "Done processing all Xen bundled guests"
}

# First merge any bundles installed via IMAGE_INSTALL, then process BUNDLED_XEN_GUESTS
ROOTFS_POSTPROCESS_COMMAND += "merge_installed_xen_bundles; bundle_xen_guests;"
