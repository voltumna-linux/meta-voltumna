# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vxn_1.0.bb
# ===========================================================================
# Target integration package for vxn (vcontainer on Xen)
# ===========================================================================
#
# This recipe installs vxn onto a Xen Dom0 target. It provides:
# - vxn CLI wrapper (docker-like interface for Xen DomU containers)
# - vrunner.sh (hypervisor-agnostic VM runner)
# - vrunner-backend-xen.sh (Xen xl backend)
# - vcontainer-common.sh (shared CLI code)
# - Kernel, initramfs, and rootfs blobs for booting DomU guests
#
# Blobs are sourced directly from the vruntime multiconfig deploy
# directory. The rootfs squashfs is unsquashed, vxn init scripts are
# injected, and it is re-squashed — all within do_compile. This keeps
# the entire dependency chain in one recipe so that SRC_URI hash
# tracking and mcdepends work correctly without relying on a separate
# deploy-only recipe (which cannot be task-depended on from a packaged
# recipe without breaking image do_rootfs sstate manifest checks).
#
# ===========================================================================
# BUILD INSTRUCTIONS
# ===========================================================================
#
# For aarch64 Dom0:
#   MACHINE=qemuarm64 bitbake vxn
#
# For x86_64 Dom0:
#   MACHINE=qemux86-64 bitbake vxn
#
# Add to a Dom0 image:
#   IMAGE_INSTALL:append = " vxn"
#
# Usage on Dom0:
#   vxn run hello-world           # Run OCI container as Xen DomU
#   vxn vmemres start             # Start persistent DomU (daemon mode)
#   vxn vexpose                   # Expose Docker API on Dom0
#
# ===========================================================================

SUMMARY = "Docker CLI for Xen-based container execution"
DESCRIPTION = "vxn provides a familiar docker-like CLI that executes commands \
               inside a Xen DomU guest with Docker. It uses the vcontainer \
               infrastructure with a Xen hypervisor backend."
HOMEPAGE = "https://git.yoctoproject.org/meta-virtualization/"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit features_check
REQUIRED_DISTRO_FEATURES = "xen"

# Host scripts + guest init scripts (all from the vcontainer files dir)
SRC_URI = "\
    file://vxn.sh \
    file://vrunner.sh \
    file://vrunner-backend-xen.sh \
    file://vrunner-backend-qemu.sh \
    file://vcontainer-common.sh \
    file://vxn-init.sh \
    file://vcontainer-init-common.sh \
    file://vxn-oci-runtime \
    file://vxn-sendtty.c \
    file://containerd-config-vxn.toml \
    file://containerd-shim-vxn-v2 \
    file://vctr \
    file://vdkr.sh \
    file://vpdmn.sh \
"

FILESEXTRAPATHS:prepend := "${THISDIR}/../../recipes-containers/vcontainer/files:"

S = "${UNPACKDIR}"
B = "${WORKDIR}/build"

# Runtime dependencies on Dom0
RDEPENDS:${PN} = "\
    xen-tools-xl \
    xen-tools-xenstore \
    bash \
    jq \
    socat \
    coreutils \
    util-linux \
    e2fsprogs \
    skopeo \
"

# squashfs-tools-native for unsquash/resquash of rootfs.img
DEPENDS += "squashfs-tools-native"

# ===========================================================================
# Architecture and multiconfig helpers
# ===========================================================================

def vxn_get_blob_arch(d):
    arch = d.getVar('TARGET_ARCH')
    if arch == 'aarch64':
        return 'aarch64'
    elif arch in ['x86_64', 'i686', 'i586']:
        return 'x86_64'
    return 'aarch64'

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

BLOB_ARCH = "${@vxn_get_blob_arch(d)}"
KERNEL_IMAGETYPE_VXN = "${@vxn_get_kernel_image_name(d)}"
VXN_MULTICONFIG = "${@vxn_get_multiconfig_name(d)}"
VXN_RUNTIME = "vdkr"

# Multiconfig deploy directory (where vdkr-rootfs-image deploys blobs)
VXN_MC_DEPLOY = "${TOPDIR}/tmp-${VXN_MULTICONFIG}/deploy/images/${MACHINE}"

# ===========================================================================
# Multiconfig dependencies — ensures blobs are built before do_compile.
# mcdepends are cross-config and don't pollute the same-config package
# dependency tree, so they don't break image do_rootfs sstate checks.
# ===========================================================================

python () {
    mc = d.getVar('VXN_MULTICONFIG')
    runtime = d.getVar('VXN_RUNTIME')
    bbmulticonfig = (d.getVar('BBMULTICONFIG') or "").split()
    if mc in bbmulticonfig:
        mcdeps = ' '.join([
            'mc::%s:%s-tiny-initramfs-image:do_image_complete' % (mc, runtime),
            'mc::%s:%s-rootfs-image:do_image_complete' % (mc, runtime),
            'mc::%s:virtual/kernel:do_deploy' % mc,
        ])
        d.setVarFlag('do_compile', 'mcdepends', mcdeps)
}

# ===========================================================================
# do_compile: source blobs from MC deploy, inject init scripts into rootfs
# ===========================================================================
# SRC_URI includes vxn-init.sh and vcontainer-init-common.sh, so their
# content hashes are part of the task signature. When they change, this
# task re-runs and produces a fresh rootfs.img with the updated scripts.

do_compile() {
    mkdir -p ${B}

    # Compile vxn-sendtty (SCM_RIGHTS helper for OCI terminal mode)
    ${CC} ${CFLAGS} ${S}/vxn-sendtty.c ${LDFLAGS} -o ${B}/vxn-sendtty

    MC_DEPLOY="${VXN_MC_DEPLOY}"

    # --- Initramfs ---
    INITRAMFS_SRC="${MC_DEPLOY}/${VXN_RUNTIME}-tiny-initramfs-image-${MACHINE}.cpio.gz"
    if [ ! -f "${INITRAMFS_SRC}" ]; then
        bbfatal "Initramfs not found at ${INITRAMFS_SRC}. Build with: bitbake mc:${VXN_MULTICONFIG}:${VXN_RUNTIME}-tiny-initramfs-image"
    fi
    cp "${INITRAMFS_SRC}" ${B}/initramfs.cpio.gz

    # --- Rootfs (unsquash, inject scripts, resquash) ---
    ROOTFS_SRC="${MC_DEPLOY}/${VXN_RUNTIME}-rootfs-image-${MACHINE}.rootfs.squashfs"
    if [ ! -f "${ROOTFS_SRC}" ]; then
        bbfatal "Rootfs not found at ${ROOTFS_SRC}. Build with: bitbake mc:${VXN_MULTICONFIG}:${VXN_RUNTIME}-rootfs-image"
    fi

    UNSQUASH_DIR="${B}/rootfs-unsquash"
    rm -rf "${UNSQUASH_DIR}"
    unsquashfs -d "${UNSQUASH_DIR}" "${ROOTFS_SRC}"

    # Inject vxn init scripts (tracked via SRC_URI → task hash changes on edit)
    install -m 0755 ${S}/vxn-init.sh ${UNSQUASH_DIR}/vxn-init.sh
    install -m 0755 ${S}/vcontainer-init-common.sh ${UNSQUASH_DIR}/vcontainer-init-common.sh

    rm -f ${B}/rootfs.img
    mksquashfs "${UNSQUASH_DIR}" ${B}/rootfs.img -noappend -comp xz
    rm -rf "${UNSQUASH_DIR}"

    # --- Kernel ---
    KERNEL_FILE="${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE_VXN}"
    if [ -f "${KERNEL_FILE}" ]; then
        cp "${KERNEL_FILE}" ${B}/kernel
    else
        bbwarn "Kernel not found at ${KERNEL_FILE}"
    fi
}

# ===========================================================================
# do_install: install CLI scripts (from SRC_URI) and blobs (from do_compile)
# ===========================================================================

do_install() {
    # Install CLI wrapper, OCI runtime, and sendtty helper
    install -d ${D}${bindir}
    install -m 0755 ${S}/vxn.sh ${D}${bindir}/vxn
    install -m 0755 ${S}/vxn-oci-runtime ${D}${bindir}/vxn-oci-runtime
    install -m 0755 ${B}/vxn-sendtty ${D}${bindir}/vxn-sendtty

    # Install containerd config (makes vxn-oci-runtime the default CRI runtime)
    install -d ${D}${sysconfdir}/containerd
    install -m 0644 ${S}/containerd-config-vxn.toml ${D}${sysconfdir}/containerd/config.toml

    # Install vxn shim wrapper: PATH trick makes runc shim find vxn-oci-runtime
    install -m 0755 ${S}/containerd-shim-vxn-v2 ${D}${bindir}/containerd-shim-vxn-v2

    # Private shim dir: runc symlink so the runc shim execs vxn-oci-runtime
    install -d ${D}${libexecdir}/vxn/shim
    ln -sf ${bindir}/vxn-oci-runtime ${D}${libexecdir}/vxn/shim/runc

    # Install vctr convenience wrapper
    install -m 0755 ${S}/vctr ${D}${bindir}/vctr

    # Docker/Podman CLI frontends (sub-packages)
    install -m 0755 ${S}/vdkr.sh ${D}${bindir}/vdkr
    install -m 0755 ${S}/vpdmn.sh ${D}${bindir}/vpdmn

    # Docker daemon config: register vxn-oci-runtime (vxn-docker-config sub-package)
    # iptables=false: Docker's default FORWARD DROP policy blocks DHCP and
    # bridged traffic for Xen DomU vifs on xenbr0. Since vxn containers are
    # full VMs with their own network stack, Docker's iptables rules are
    # unnecessary and harmful. Note: bridge networking is left enabled so
    # that 'docker pull' works (needs bridge for DNS). Users must pass
    # --network=none for 'docker run' (veth/netns incompatible with VMs).
    install -d ${D}${sysconfdir}/docker
    printf '{\n  "runtimes": {\n    "vxn": {\n      "path": "/usr/bin/vxn-oci-runtime"\n    }\n  },\n  "default-runtime": "vxn",\n  "iptables": false\n}\n' \
        > ${D}${sysconfdir}/docker/daemon.json

    # Podman config: register vxn-oci-runtime (vxn-podman-config sub-package)
    install -d ${D}${sysconfdir}/containers/containers.conf.d
    printf '[engine]\nruntime = "vxn"\n\n[engine.runtimes]\nvxn = ["/usr/bin/vxn-oci-runtime"]\n' \
        > ${D}${sysconfdir}/containers/containers.conf.d/50-vxn-runtime.conf

    # Install shared scripts into libdir
    install -d ${D}${libdir}/vxn
    install -m 0755 ${S}/vrunner.sh ${D}${libdir}/vxn/
    install -m 0755 ${S}/vrunner-backend-xen.sh ${D}${libdir}/vxn/
    install -m 0755 ${S}/vrunner-backend-qemu.sh ${D}${libdir}/vxn/
    install -m 0644 ${S}/vcontainer-common.sh ${D}${libdir}/vxn/

    # Install blobs from do_compile output
    install -d ${D}${datadir}/vxn/${BLOB_ARCH}

    if [ -f "${B}/kernel" ]; then
        install -m 0644 "${B}/kernel" ${D}${datadir}/vxn/${BLOB_ARCH}/${KERNEL_IMAGETYPE_VXN}
        bbnote "Installed kernel ${KERNEL_IMAGETYPE_VXN}"
    else
        bbwarn "Kernel blob not found in build dir"
    fi

    if [ -f "${B}/initramfs.cpio.gz" ]; then
        install -m 0644 "${B}/initramfs.cpio.gz" ${D}${datadir}/vxn/${BLOB_ARCH}/
        bbnote "Installed initramfs"
    else
        bbwarn "Initramfs blob not found in build dir"
    fi

    if [ -f "${B}/rootfs.img" ]; then
        install -m 0644 "${B}/rootfs.img" ${D}${datadir}/vxn/${BLOB_ARCH}/
        bbnote "Installed rootfs.img"
    else
        bbwarn "Rootfs blob not found in build dir"
    fi
}

# Sub-packages for CLI frontends and native runtime config
PACKAGES =+ "${PN}-vdkr ${PN}-vpdmn ${PN}-docker-config ${PN}-podman-config"

FILES:${PN}-vdkr = "${bindir}/vdkr"
FILES:${PN}-vpdmn = "${bindir}/vpdmn"
FILES:${PN}-docker-config = "${sysconfdir}/docker/daemon.json"
FILES:${PN}-podman-config = "${sysconfdir}/containers/containers.conf.d/50-vxn-runtime.conf"

RDEPENDS:${PN}-vdkr = "${PN} bash"
RDEPENDS:${PN}-vpdmn = "${PN} bash"
RDEPENDS:${PN}-docker-config = "${PN} docker"
RDEPENDS:${PN}-podman-config = "${PN} podman"

# daemon.json conflicts with docker-registry-config (only one provider)
RCONFLICTS:${PN}-docker-config = "docker-registry-config"

FILES:${PN} = "\
    ${bindir}/vxn \
    ${bindir}/vxn-oci-runtime \
    ${bindir}/vxn-sendtty \
    ${bindir}/containerd-shim-vxn-v2 \
    ${bindir}/vctr \
    ${libexecdir}/vxn/ \
    ${sysconfdir}/containerd/config.toml \
    ${libdir}/vxn/ \
    ${datadir}/vxn/ \
"

# Blobs are large binary files
INSANE_SKIP:${PN} += "already-stripped"
