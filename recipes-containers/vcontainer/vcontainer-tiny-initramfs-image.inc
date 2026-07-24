# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vcontainer-tiny-initramfs-image.inc
# ===========================================================================
# Shared tiny initramfs image for vdkr/vpdmn switch_root boot flow
# ===========================================================================
#
# This produces a minimal cpio.gz initramfs containing only:
#   - busybox (for mount, switch_root, sh, etc.)
#   - vcontainer-preinit (the /init script)
#
# Boot flow:
#   QEMU boots kernel + this initramfs
#   -> /init (vcontainer-preinit) mounts squashfs rootfs.img from /dev/vda
#   -> switch_root into rootfs.img with overlayfs
#   -> ${runtime}-init.sh runs with full container tools
#

SUMMARY = "Tiny initramfs for vcontainer switch_root"
DESCRIPTION = "Minimal initramfs containing busybox and preinit script for \
               mounting squashfs rootfs and performing switch_root."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image

# Minimal packages: just busybox and the preinit script
# busybox provides: mount, switch_root, sh, mkdir, sleep, cat, ls, echo, reboot
PACKAGE_INSTALL = "busybox vcontainer-preinit"

# No extra features - keep it tiny
IMAGE_FEATURES = ""

# Don't include kernel in initramfs
PACKAGE_EXCLUDE = "kernel-image-*"

# Output as cpio.gz (standard initramfs format)
IMAGE_FSTYPES = "${INITRAMFS_FSTYPES}"

# Keep the image small
IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# No locales needed
IMAGE_LINGUAS = ""

# Suppress the suffix for cleaner naming
IMAGE_NAME_SUFFIX = ""

# Compatible with x86_64 and aarch64 targets
COMPATIBLE_HOST = "(x86_64|aarch64).*-linux"

# Create required directories that busybox/preinit expect
ROOTFS_POSTPROCESS_COMMAND += "create_initramfs_dirs;"

create_initramfs_dirs() {
    # Create mount points used by preinit
    install -d ${IMAGE_ROOTFS}/proc
    install -d ${IMAGE_ROOTFS}/sys
    install -d ${IMAGE_ROOTFS}/dev
    install -d ${IMAGE_ROOTFS}/mnt/lower
    install -d ${IMAGE_ROOTFS}/mnt/upper
    install -d ${IMAGE_ROOTFS}/mnt/work
    install -d ${IMAGE_ROOTFS}/mnt/root

    # Create console device node (needed before /dev is mounted)
    mknod -m 622 ${IMAGE_ROOTFS}/dev/console c 5 1 2>/dev/null || true
}
