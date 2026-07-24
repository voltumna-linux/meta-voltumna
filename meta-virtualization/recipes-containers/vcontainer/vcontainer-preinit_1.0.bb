# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vcontainer-preinit_1.0.bb
# ===========================================================================
# Package containing the preinit script for vcontainer tiny initramfs
# ===========================================================================
#
# This package installs the preinit script as /init for use in a tiny
# initramfs. The script:
#   1. Mounts essential filesystems (/proc, /sys, /dev)
#   2. Mounts the squashfs rootfs from /dev/vda with overlayfs
#   3. Executes switch_root to the real root filesystem
#
# Used by: vdkr-tiny-initramfs-image.bb, vpdmn-tiny-initramfs-image.bb
#

SUMMARY = "Preinit script for vcontainer initramfs"
DESCRIPTION = "Minimal init script that mounts squashfs rootfs with overlayfs \
               and performs switch_root for vcontainer QEMU environment."
HOMEPAGE = "https://git.yoctoproject.org/meta-virtualization/"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

SRC_URI = "file://vcontainer-preinit.sh"

S = "${UNPACKDIR}"

# This package only provides the init script - no dependencies
# The initramfs image will pull in busybox separately
RDEPENDS:${PN} = ""

do_install() {
    install -d ${D}
    install -m 0755 ${S}/vcontainer-preinit.sh ${D}/init
}

# Package the /init script
FILES:${PN} = "/init"

# Prevent QA warnings about /init location
INSANE_SKIP:${PN} += "file-rdeps"
