# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vcontainer-native.bb
# ===========================================================================
# Native recipe providing vrunner.sh for container cross-installation
# ===========================================================================
#
# This recipe installs vrunner.sh into the native sysroot so that
# container-bundle.bbclass and container-cross-install.bbclass can use it
# to cross-install containers into target images.
#
# Note: This does NOT build the blobs. Blobs must be built separately via
# multiconfig (see vdkr-initramfs-create, vpdmn-initramfs-create).
#
# ===========================================================================

SUMMARY = "Container cross-install runner script"
DESCRIPTION = "Provides vrunner.sh for cross-installing containers into images"
HOMEPAGE = "https://git.yoctoproject.org/meta-virtualization/"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit native

# Runtime dependencies for vrunner.sh
DEPENDS = "coreutils-native socat-native"

SRC_URI = "\
    file://vrunner.sh \
    file://vrunner-backend-qemu.sh \
    file://vrunner-backend-xen.sh \
    file://vcontainer-common.sh \
"

S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/vrunner.sh ${D}${bindir}/vrunner.sh
    install -m 0755 ${S}/vrunner-backend-qemu.sh ${D}${bindir}/vrunner-backend-qemu.sh
    install -m 0755 ${S}/vrunner-backend-xen.sh ${D}${bindir}/vrunner-backend-xen.sh
    install -m 0644 ${S}/vcontainer-common.sh ${D}${bindir}/vcontainer-common.sh
}

BBCLASSEXTEND = "native"
