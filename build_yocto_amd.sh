#!/bin/bash

# Function to display help information
display_help() {
    echo "Usage: $0 <board_name> <image_type> <yocto_branch>"
    echo ""
    echo "Arguments:"
    echo "  <board_name>  Specify the board type ('v3000')."
    echo "  <image_type>  Specify the image type ('core-image-minimal', 'core-image-sato)."
    echo "  <yocto_branch>  Specify the yocto branch('scarthgap')."
    echo ""
    echo "Available boards:"
    echo "  v3000"
    echo "  turin"
    echo "  siena"
    echo ""
    echo "Available image types:"
    echo "  core-image-minimal"
    echo "  core-image-sato"
    echo ""
    echo "Available yocto branch:"
    echo "  scarthgap"
    exit 1
}

# Function to update local.conf with new values
update_distro_in_local_conf() {
    local conf_file="$1"
    local new_distro="$2"

    if grep -q '^DISTRO=' "$conf_file"; then
        echo "Updating existing DISTRO value in $conf_file..."
        sed -i "s/^DISTRO=.*/DISTRO=\"$new_distro\"/" "$conf_file"
    else
        echo "Adding DISTRO to $conf_file..."
        echo "DISTRO=\"$new_distro\"" >> "$conf_file"
    fi
}

update_distro_feature_in_local_conf() {
    local conf_file="$1"
    local new_distro_feature="$2"

    if grep -q '^DISTRO_FEATURES:append=' "$conf_file"; then
        echo "Updating existing DISTRO_FEATURES:append value in $conf_file..."
        sed -i "s/^DISTRO_FEATURES:append=.*/DISTRO_FEATURES:append=\"$new_distro_feature\"/" "$conf_file"
    else
        echo "Adding DISTRO_FEATURES:append to $conf_file..."
        echo "DISTRO_FEATURES:append=\"$new_distro_feature\"" >> "$conf_file"
    fi
}

# Check if at least two arguments are provided
if [ "$#" -ne 3 ]; then
    display_help
fi

# Extract command-line arguments
BOARD_NAME="$1"
IMAGE_TYPE="$2"
YOCTO_BRANCH="$3"
# Set MACHINE and TEMPLATECONF based on board name
case "$BOARD_NAME" in
	v3000)
        MACHINE="v3000"
        TEMPLATECONF="${TOPDIR}/meta-amd/meta-amd-bsp/conf/templates/v3000/"
        ;;
	turin)
        MACHINE="turin"
        TEMPLATECONF="${TOPDIR}/meta-amd/meta-amd-bsp/conf/templates/turin/"
        ;;
	siena)
	MACHINE="siena"
        TEMPLATECONF="${TOPDIR}/meta-amd/meta-amd-bsp/conf/templates/siena/"
        ;;
    *)
        echo "ERROR: Unsupported board name '$BOARD_NAME'."
        display_help
        ;;
esac

# Export the TEMPLATECONF path
export TEMPLATECONF

# Define the path to the oe-init-build-env script
OE_INIT_BUILD_ENV_PATH="${PWD}/oe-init-build-env"
source "$OE_INIT_BUILD_ENV_PATH" build-${MACHINE}-${YOCTO_BRANCH}

LOCAL_CONF_PATH="conf/local.conf"

# Determine DISTRO and features based on IMAGE_TYPE
case "$IMAGE_TYPE" in
    core-image-minimal)
	DISTRO="nodistro"
        DISTRO_FEATURE=" systemd"
	sed -i '/^BBMASK+/d' "$LOCAL_CONF_PATH"
        update_distro_in_local_conf "$LOCAL_CONF_PATH" "$DISTRO"
        update_distro_feature_in_local_conf "$LOCAL_CONF_PATH" "$DISTRO_FEATURE"
	echo 'BBMASK+="recipes-core/initrdscripts/initramfs-module-install-efi_1.0.bbappend"' >> "$LOCAL_CONF_PATH"
        bitbake core-image-minimal -k
        ;;
    core-image-sato)
	DISTRO="poky-amd"
        DISTRO_FEATURE=" systemd wayland polkit pam opengl vulkan"
	sed -i '/^BBMASK+/d' "$LOCAL_CONF_PATH"
	update_distro_in_local_conf "$LOCAL_CONF_PATH" "$DISTRO"
        update_distro_feature_in_local_conf "$LOCAL_CONF_PATH" "$DISTRO_FEATURE"
	echo 'BBMASK+="recipes-core/initrdscripts/initramfs-module-install-efi_1.0.bbappend"' >> "$LOCAL_CONF_PATH"
        bitbake core-image-sato -k
        ;;
    *)
        echo "ERROR: Unsupported image type '$IMAGE_TYPE'."
        exit 1
        ;;
esac

echo "Configuration updated successfully."
