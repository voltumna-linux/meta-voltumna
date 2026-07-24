# example-xen-guest-bundle_1.0.bb
# ===========================================================================
# Example Xen guest bundle recipe demonstrating xen-guest-bundle.bbclass
# ===========================================================================
#
# This recipe shows how to create a package that bundles Xen guest images.
# When installed via IMAGE_INSTALL into a Dom0 image that inherits
# xen-guest-cross-install, the guests are automatically deployed.
#
# Usage in image recipe (e.g., xen-image-minimal.bb):
#   IMAGE_INSTALL += "example-xen-guest-bundle"
#
# Or in local.conf (use pn- override for specific images):
#   IMAGE_INSTALL:append:pn-xen-image-minimal = " example-xen-guest-bundle"
#
# IMPORTANT: Do NOT use global IMAGE_INSTALL:append without pn- override!
# This causes circular dependencies when guest images try to include
# the bundle that depends on them.
#
# ===========================================================================

SUMMARY = "Example Xen guest bundle"
DESCRIPTION = "Demonstrates xen-guest-bundle.bbclass by bundling the \
               xen-guest-image-minimal guest. Use this as a template \
               for your own Xen guest bundles."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit xen-guest-bundle features_check

# matches xen-guest-image-minimal recipe
REQUIRED_DISTRO_FEATURES += "${@bb.utils.contains('IMAGE_FEATURES', 'x11', ' x11', '', d)} xen"

# Define guests to bundle
# Format: recipe-name[:autostart][:external]
#
# recipe-name: Yocto image recipe that produces the guest rootfs
# autostart:   Creates symlink in /etc/xen/auto/ for xendomains
# external:    Skip dependency generation (pre-built/3rd-party guest)
XEN_GUEST_BUNDLES = "\
    xen-guest-image-minimal:autostart \
"

# Per-guest configuration via varflags (optional):
XEN_GUEST_MEMORY[xen-guest-image-minimal] = "1024"
# XEN_GUEST_VCPUS[xen-guest-image-minimal] = "2"
# XEN_GUEST_VIF[xen-guest-image-minimal] = "bridge=xenbr0"
# XEN_GUEST_EXTRA[xen-guest-image-minimal] = "root=/dev/xvda ro console=hvc0 ip=dhcp"

# Custom config file (replaces auto-generation):
# SRC_URI += "file://my-custom-guest.cfg"
# XEN_GUEST_CONFIG_FILE[xen-guest-image-minimal] = "${UNPACKDIR}/my-custom-guest.cfg"

# External guest example (rootfs/kernel already in DEPLOY_DIR_IMAGE):
# XEN_GUEST_BUNDLES += "my-vendor-guest:external"
# XEN_GUEST_ROOTFS[my-vendor-guest] = "vendor-rootfs.ext4"
# XEN_GUEST_KERNEL[my-vendor-guest] = "vendor-kernel"
