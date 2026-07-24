# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vxn-initramfs-create_1.0.bb
# ===========================================================================
# Builds Xen DomU boot blobs for vxn
# ===========================================================================
#
# This recipe packages boot blobs for vxn (vcontainer on Xen):
# - A tiny initramfs (reused from vdkr/vpdmn build)
# - The rootfs.img squashfs (same as vdkr, with HV detection in init)
# - The kernel (Xen PV-capable via vxn.cfg fragment in vruntime)
#
# Boot flow on Xen Dom0:
#   xl create domain.cfg
#   -> Xen boots kernel + tiny initramfs in DomU
#   -> preinit detects Xen block prefix, mounts rootfs.img from /dev/xvda
#   -> switch_root into rootfs.img
#   -> vdkr-init.sh detects Xen via /proc/xen, uses xvd* devices
#
# ===========================================================================
# BUILD INSTRUCTIONS
# ===========================================================================
#
# For aarch64:
#   MACHINE=qemuarm64 bitbake vxn-initramfs-create
#
# For x86_64:
#   MACHINE=qemux86-64 bitbake vxn-initramfs-create
#
# Blobs are deployed to: tmp/deploy/images/${MACHINE}/vxn/
#
# ===========================================================================

SUMMARY = "Build Xen DomU boot blobs for vxn"
DESCRIPTION = "Packages kernel, initramfs and rootfs for running \
               vcontainer workloads as Xen DomU guests."

# Source blobs from vdkr (Docker) build - same rootfs works under Xen
VXN_RUNTIME = "vdkr"

require vxn-initramfs-create.inc
