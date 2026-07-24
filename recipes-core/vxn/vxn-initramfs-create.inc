# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vxn-initramfs-create.inc
# ===========================================================================
# Shared code for building Xen DomU boot blobs for vxn
# ===========================================================================
#
# This .inc file packages boot blobs for vxn (vcontainer on Xen).
# It reuses the same initramfs and rootfs images built by vruntime
# multiconfig (same images as vdkr/vpdmn), since the init scripts
# detect the hypervisor at boot time.
#
# The kernel from vruntime already includes Xen PV support via vxn.cfg
# fragment (added to DISTRO_FEATURES in vruntime.conf).
#
# Required variables from including recipe:
#   VXN_RUNTIME - runtime to source blobs from ("vdkr" or "vpdmn")
#
# Boot flow on Xen Dom0:
#   xl create <domain.cfg>
#   -> Xen boots kernel + tiny initramfs in DomU
#   -> preinit mounts rootfs.img from /dev/xvda
#   -> switch_root into rootfs.img
#   -> init detects Xen, uses /dev/xvd* and trans=xen
#
# ===========================================================================

HOMEPAGE = "https://git.yoctoproject.org/meta-virtualization/"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit deploy

EXCLUDE_FROM_WORLD = "1"
DEPENDS = "squashfs-tools-native"

# Default to vdkr (Docker) as the source runtime
VXN_RUNTIME ?= "vdkr"

# Always rebuild - init script injection must not be sstate-cached
# because the rootfs.img content comes from the deploy dir (untracked)
SSTATE_SKIP_CREATION = "1"
do_compile[nostamp] = "1"
do_deploy[nostamp] = "1"

python () {

    mc = d.getVar('VXN_MULTICONFIG')
    runtime = d.getVar('VXN_RUNTIME')
    bbmulticonfig = (d.getVar('BBMULTICONFIG') or "").split()
    if mc in bbmulticonfig:
        # All blobs come from the vruntime multiconfig - kernel, initramfs, rootfs
        mcdeps = ' '.join([
            'mc::%s:%s-tiny-initramfs-image:do_image_complete' % (mc, runtime),
            'mc::%s:%s-rootfs-image:do_image_complete' % (mc, runtime),
            'mc::%s:virtual/kernel:do_deploy' % mc,
        ])
        d.setVarFlag('do_compile', 'mcdepends', mcdeps)
}

INHIBIT_DEFAULT_DEPS = "1"

# Init scripts to inject into the rootfs squashfs
FILESEXTRAPATHS:prepend := "${THISDIR}/../../recipes-containers/vcontainer/files:"
SRC_URI = "\
    file://vxn-init.sh \
    file://vcontainer-init-common.sh \
"

S = "${UNPACKDIR}"
B = "${WORKDIR}/build"

def vxn_get_kernel_image_name(d):
    arch = d.getVar('TARGET_ARCH')
    if arch == 'aarch64':
        return 'Image'
    elif arch in ['x86_64', 'i686', 'i586']:
        return 'bzImage'
    elif arch == 'arm':
        return 'zImage'
    return 'Image'

def vxn_get_multiconfig_name(d):
    arch = d.getVar('TARGET_ARCH')
    if arch == 'aarch64':
        return 'vruntime-aarch64'
    elif arch in ['x86_64', 'i686', 'i586']:
        return 'vruntime-x86-64'
    return 'vruntime-aarch64'

def vxn_get_blob_arch(d):
    arch = d.getVar('TARGET_ARCH')
    if arch == 'aarch64':
        return 'aarch64'
    elif arch in ['x86_64', 'i686', 'i586']:
        return 'x86_64'
    return 'aarch64'

KERNEL_IMAGETYPE_INITRAMFS = "${@vxn_get_kernel_image_name(d)}"
VXN_MULTICONFIG = "${@vxn_get_multiconfig_name(d)}"
BLOB_ARCH = "${@vxn_get_blob_arch(d)}"

VXN_MC_DEPLOY = "${TOPDIR}/tmp-${VXN_MULTICONFIG}/deploy/images/${MACHINE}"

do_compile() {
    mkdir -p ${B}

    MC_TMPDIR="${TOPDIR}/tmp-${VXN_MULTICONFIG}"
    MC_DEPLOY="${MC_TMPDIR}/deploy/images/${MACHINE}"

    # =========================================================================
    # PART 1: COPY TINY INITRAMFS (same as vdkr/vpdmn)
    # =========================================================================
    bbnote "Copying tiny initramfs from image build..."

    INITRAMFS_SRC="${MC_DEPLOY}/${VXN_RUNTIME}-tiny-initramfs-image-${MACHINE}.cpio.gz"

    if [ ! -f "${INITRAMFS_SRC}" ]; then
        bbfatal "Initramfs not found at ${INITRAMFS_SRC}. Build it first with: bitbake mc:${VXN_MULTICONFIG}:${VXN_RUNTIME}-tiny-initramfs-image"
    fi

    cp "${INITRAMFS_SRC}" ${B}/initramfs.cpio.gz
    INITRAMFS_SIZE=$(stat -c%s ${B}/initramfs.cpio.gz)
    bbnote "Initramfs copied: ${INITRAMFS_SIZE} bytes ($(expr ${INITRAMFS_SIZE} / 1024)KB)"

    # =========================================================================
    # PART 2: COPY ROOTFS (same squashfs, works under both QEMU and Xen)
    # =========================================================================
    bbnote "Copying rootfs from image build..."

    ROOTFS_SRC="${MC_DEPLOY}/${VXN_RUNTIME}-rootfs-image-${MACHINE}.rootfs.squashfs"

    if [ ! -f "${ROOTFS_SRC}" ]; then
        bbfatal "Rootfs image not found at ${ROOTFS_SRC}. Build it first with: bitbake mc:${VXN_MULTICONFIG}:${VXN_RUNTIME}-rootfs-image"
    fi

    cp "${ROOTFS_SRC}" ${B}/rootfs.img
    ROOTFS_SIZE=$(stat -c%s ${B}/rootfs.img)
    bbnote "Rootfs image copied: ${ROOTFS_SIZE} bytes ($(expr ${ROOTFS_SIZE} / 1024 / 1024)MB)"

    # Inject vxn init scripts into the rootfs squashfs
    bbnote "Injecting vxn init scripts into rootfs..."
    UNSQUASH_DIR="${B}/rootfs-unsquash"
    rm -rf "${UNSQUASH_DIR}"
    unsquashfs -d "${UNSQUASH_DIR}" ${B}/rootfs.img
    install -m 0755 ${S}/vxn-init.sh ${UNSQUASH_DIR}/vxn-init.sh
    install -m 0755 ${S}/vcontainer-init-common.sh ${UNSQUASH_DIR}/vcontainer-init-common.sh
    rm -f ${B}/rootfs.img
    mksquashfs "${UNSQUASH_DIR}" ${B}/rootfs.img -noappend -comp xz
    rm -rf "${UNSQUASH_DIR}"
    ROOTFS_SIZE=$(stat -c%s ${B}/rootfs.img)
    bbnote "Rootfs with vxn init scripts: ${ROOTFS_SIZE} bytes ($(expr ${ROOTFS_SIZE} / 1024 / 1024)MB)"

    # =========================================================================
    # PART 3: COPY KERNEL (Xen PV-capable via vxn.cfg fragment)
    # =========================================================================
    bbnote "Copying kernel image..."
    KERNEL_FILE="${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE_INITRAMFS}"
    if [ -f "${KERNEL_FILE}" ]; then
        cp "${KERNEL_FILE}" ${B}/kernel
        KERNEL_SIZE=$(stat -c%s ${B}/kernel)
        bbnote "Kernel copied: ${KERNEL_SIZE} bytes ($(expr ${KERNEL_SIZE} / 1024 / 1024)MB)"
    else
        bbwarn "Kernel not found at ${KERNEL_FILE}"
    fi
}

# This is a deploy-only recipe - no packages produced.
# PACKAGES="" prevents the rootfs task from looking for package manifests.
PACKAGES = ""
do_install[noexec] = "1"
do_package[noexec] = "1"
do_packagedata[noexec] = "1"
do_package_write_rpm[noexec] = "1"
do_package_write_ipk[noexec] = "1"
do_package_write_deb[noexec] = "1"
do_populate_sysroot[noexec] = "1"

do_deploy() {
    install -d ${DEPLOYDIR}/vxn/${BLOB_ARCH}

    if [ -f ${B}/initramfs.cpio.gz ]; then
        install -m 0644 ${B}/initramfs.cpio.gz ${DEPLOYDIR}/vxn/${BLOB_ARCH}/
        bbnote "Deployed initramfs.cpio.gz to vxn/${BLOB_ARCH}/"
    fi

    if [ -f ${B}/rootfs.img ]; then
        install -m 0644 ${B}/rootfs.img ${DEPLOYDIR}/vxn/${BLOB_ARCH}/
        bbnote "Deployed rootfs.img to vxn/${BLOB_ARCH}/"
    fi

    if [ -f ${B}/kernel ]; then
        install -m 0644 ${B}/kernel ${DEPLOYDIR}/vxn/${BLOB_ARCH}/${KERNEL_IMAGETYPE_INITRAMFS}
        bbnote "Deployed kernel as vxn/${BLOB_ARCH}/${KERNEL_IMAGETYPE_INITRAMFS}"
    fi

    cat > ${DEPLOYDIR}/vxn/${BLOB_ARCH}/README << EOF
vxn Boot Blobs (Xen DomU)
==========================

Built for: ${TARGET_ARCH}
Machine: ${MACHINE}
Multiconfig: ${VXN_MULTICONFIG}
Source runtime: ${VXN_RUNTIME}
Date: $(date)

Files:
  ${KERNEL_IMAGETYPE_INITRAMFS}  - Kernel image (Xen PV-capable)
  initramfs.cpio.gz              - Tiny initramfs (busybox + preinit)
  rootfs.img                     - Root filesystem with container tools

Boot flow:
  xl create <domain.cfg>
  -> Xen boots kernel + initramfs in DomU
  -> preinit detects Xen, mounts rootfs.img from /dev/xvda
  -> switch_root into rootfs.img
  -> init script runs container commands
EOF
}

addtask deploy after do_compile before do_build
