# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vcontainer-initramfs-create.inc
# ===========================================================================
# Shared code for building QEMU boot blobs (vdkr/vpdmn) - Image-based approach
# ===========================================================================
#
# This .inc file contains common code for building boot blobs using
# a proper Yocto image-based initramfs instead of extracting files.
#
# Required variables from including recipe:
#   VCONTAINER_RUNTIME - "vdkr" or "vpdmn"
#
# Boot flow:
#   QEMU boots kernel + tiny initramfs (cpio.gz from image recipe)
#   -> preinit mounts rootfs.img from /dev/vda
#   -> switch_root into rootfs.img
#   -> ${VCONTAINER_RUNTIME}-init.sh runs
#
# ===========================================================================

HOMEPAGE = "https://git.yoctoproject.org/meta-virtualization/"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit deploy

# Not built by default - user must explicitly request via bitbake or vcontainer-native
EXCLUDE_FROM_WORLD = "1"

# No extraction tools needed - we use pre-built images
DEPENDS = ""

# Force rebuild control:
# Set VCONTAINER_FORCE_BUILD = "1" in local.conf to disable stamp caching
# and force compile/deploy to always run. Useful when debugging dependency issues.
# Default: use normal stamp caching for faster incremental builds
VCONTAINER_FORCE_BUILD ?= ""
python () {
    if d.getVar('VCONTAINER_FORCE_BUILD') == '1':
        d.setVar('SSTATE_SKIP_CREATION', '1')
        d.setVarFlag('do_compile', 'nostamp', '1')
        d.setVarFlag('do_deploy', 'nostamp', '1')

}

# Only populate native sysroot, skip target sysroot to avoid libgcc conflicts
INHIBIT_DEFAULT_DEPS = "1"

# Dependencies:
# 1. The tiny initramfs image (produces cpio.gz)
# 2. The multiconfig rootfs image (produces squashfs)
# 3. The kernel (deployed transitively via image.bbclass do_build)
#
# Both image recipes inherit core-image/image.bbclass which has:
#   do_build[depends] += "virtual/kernel:do_deploy"
# By depending on do_build (not do_image_complete), we ensure the
# kernel is deployed to MC_DEPLOY before do_compile copies it.
# Using do_image_complete cut the chain short — it runs before
# do_build, so virtual/kernel:do_deploy was not guaranteed to have
# run, causing missing kernel on sstate-accelerated builds.
do_compile[depends] = "${VCONTAINER_RUNTIME}-tiny-initramfs-image:do_build"
do_compile[depends] += "${VCONTAINER_RUNTIME}-rootfs-image:do_build"

S = "${UNPACKDIR}"
B = "${WORKDIR}/build"

def get_kernel_image_name(d):
    arch = d.getVar('TARGET_ARCH')
    if arch == 'aarch64':
        return 'Image'
    elif arch in ['x86_64', 'i686', 'i586']:
        return 'bzImage'
    elif arch == 'arm':
        return 'zImage'
    return 'Image'

def get_multiconfig_name(d):
    arch = d.getVar('TARGET_ARCH')
    if arch == 'aarch64':
        return 'vruntime-aarch64'
    elif arch in ['x86_64', 'i686', 'i586']:
        return 'vruntime-x86-64'
    return 'vruntime-aarch64'

def get_blob_arch(d):
    """Map TARGET_ARCH to vrunner blob architecture (aarch64 or x86_64)"""
    arch = d.getVar('TARGET_ARCH')
    if arch == 'aarch64':
        return 'aarch64'
    elif arch in ['x86_64', 'i686', 'i586']:
        return 'x86_64'
    return 'aarch64'

KERNEL_IMAGETYPE_INITRAMFS = "${@get_kernel_image_name(d)}"
VCONTAINER_MULTICONFIG = "${@get_multiconfig_name(d)}"
BLOB_ARCH = "${@get_blob_arch(d)}"

# Path to the multiconfig build output
VCONTAINER_MC_DEPLOY = "${TOPDIR}/tmp-${VCONTAINER_MULTICONFIG}/deploy/images/${MACHINE}"

do_compile() {
    mkdir -p ${B}

    MC_TMPDIR="${TOPDIR}/tmp-${VCONTAINER_MULTICONFIG}"
    MC_DEPLOY="${MC_TMPDIR}/deploy/images/${MACHINE}"

    # =========================================================================
    # PART 1: COPY TINY INITRAMFS (cpio.gz from image recipe)
    # =========================================================================
    bbnote "Copying tiny initramfs from image build..."

    INITRAMFS_SRC="${MC_DEPLOY}/${VCONTAINER_RUNTIME}-tiny-initramfs-image-${MACHINE}.cpio.gz"

    if [ ! -f "${INITRAMFS_SRC}" ]; then
        bbfatal "Initramfs not found at ${INITRAMFS_SRC}. Build it first with: bitbake mc:${VCONTAINER_MULTICONFIG}:${VCONTAINER_RUNTIME}-tiny-initramfs-image"
    fi

    cp "${INITRAMFS_SRC}" ${B}/initramfs.cpio.gz
    INITRAMFS_SIZE=$(stat -c%s ${B}/initramfs.cpio.gz)
    bbnote "Initramfs copied: ${INITRAMFS_SIZE} bytes ($(expr ${INITRAMFS_SIZE} / 1024)KB)"

    # =========================================================================
    # PART 2: COPY ROOTFS (squashfs from image recipe)
    # =========================================================================
    bbnote "Copying rootfs from image build..."

    ROOTFS_SRC="${MC_DEPLOY}/${VCONTAINER_RUNTIME}-rootfs-image-${MACHINE}.rootfs.squashfs"

    if [ ! -f "${ROOTFS_SRC}" ]; then
        bbfatal "Rootfs image not found at ${ROOTFS_SRC}. Build it first with: bitbake mc:${VCONTAINER_MULTICONFIG}:${VCONTAINER_RUNTIME}-rootfs-image"
    fi

    cp "${ROOTFS_SRC}" ${B}/rootfs.img
    ROOTFS_SIZE=$(stat -c%s ${B}/rootfs.img)
    bbnote "Rootfs image copied: ${ROOTFS_SIZE} bytes ($(expr ${ROOTFS_SIZE} / 1024 / 1024)MB)"

    # =========================================================================
    # PART 3: COPY KERNEL
    # =========================================================================
    # Use the multiconfig's deploy directory (same as initramfs/rootfs),
    # not DEPLOY_DIR_IMAGE which may point to the main config's deploy
    # directory. The kernel is built as a dependency of the rootfs image
    # within the same multiconfig.
    bbnote "Copying kernel image..."
    KERNEL_FILE="${MC_DEPLOY}/${KERNEL_IMAGETYPE_INITRAMFS}"
    if [ -f "${KERNEL_FILE}" ]; then
        cp "${KERNEL_FILE}" ${B}/kernel
        KERNEL_SIZE=$(stat -c%s ${B}/kernel)
        bbnote "Kernel copied: ${KERNEL_SIZE} bytes ($(expr ${KERNEL_SIZE} / 1024 / 1024)MB)"
    else
        bbwarn "Kernel not found at ${KERNEL_FILE} — check that the vruntime multiconfig kernel is built"
    fi
}

do_install[noexec] = "1"
do_package[noexec] = "1"
do_packagedata[noexec] = "1"
do_package_write_rpm[noexec] = "1"
do_package_write_ipk[noexec] = "1"
do_package_write_deb[noexec] = "1"
do_populate_sysroot[noexec] = "1"

do_deploy() {
    # Deploy to ${VCONTAINER_RUNTIME}/<arch> subdirectory
    install -d ${DEPLOYDIR}/${VCONTAINER_RUNTIME}/${BLOB_ARCH}

    if [ -f ${B}/initramfs.cpio.gz ]; then
        install -m 0644 ${B}/initramfs.cpio.gz ${DEPLOYDIR}/${VCONTAINER_RUNTIME}/${BLOB_ARCH}/
        bbnote "Deployed initramfs.cpio.gz to ${VCONTAINER_RUNTIME}/${BLOB_ARCH}/"
    fi

    if [ -f ${B}/rootfs.img ]; then
        install -m 0644 ${B}/rootfs.img ${DEPLOYDIR}/${VCONTAINER_RUNTIME}/${BLOB_ARCH}/
        bbnote "Deployed rootfs.img to ${VCONTAINER_RUNTIME}/${BLOB_ARCH}/"
    fi

    if [ -f ${B}/kernel ]; then
        install -m 0644 ${B}/kernel ${DEPLOYDIR}/${VCONTAINER_RUNTIME}/${BLOB_ARCH}/${KERNEL_IMAGETYPE_INITRAMFS}
        bbnote "Deployed kernel as ${VCONTAINER_RUNTIME}/${BLOB_ARCH}/${KERNEL_IMAGETYPE_INITRAMFS}"
    fi

    cat > ${DEPLOYDIR}/${VCONTAINER_RUNTIME}/${BLOB_ARCH}/README << EOF
${VCONTAINER_RUNTIME} Boot Blobs
==================

Built for: ${TARGET_ARCH}
Machine: ${MACHINE}
Multiconfig: ${VCONTAINER_MULTICONFIG}
Date: $(date)

Files:
  ${KERNEL_IMAGETYPE_INITRAMFS}  - Kernel image for QEMU
  initramfs.cpio.gz              - Tiny initramfs (busybox + preinit)
  rootfs.img                     - Root filesystem with container tools

Boot flow:
  QEMU boots kernel + initramfs
  -> preinit mounts rootfs.img from /dev/vda
  -> switch_root into rootfs.img
  -> ${VCONTAINER_RUNTIME}-init.sh runs container commands
EOF
}

addtask deploy after do_compile before do_build
