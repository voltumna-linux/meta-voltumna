# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vdkr-initramfs-create_1.0.bb
# ===========================================================================
# Builds QEMU boot blobs for vdkr (Docker CLI)
# ===========================================================================
#
# This recipe packages the boot blobs for vdkr:
# - A tiny initramfs with just busybox for switch_root
# - The rootfs.img squashfs image (built via multiconfig)
# - The kernel
#
# Boot flow:
#   QEMU boots kernel + tiny initramfs
#   -> preinit mounts rootfs.img from /dev/vda
#   -> switch_root into rootfs.img
#   -> vdkr-init.sh runs with a real root filesystem
#   -> Docker can use pivot_root properly
#
# ===========================================================================
# BUILD INSTRUCTIONS
# ===========================================================================
#
# For aarch64 (multiconfig dependency is automatic):
#   MACHINE=qemuarm64 bitbake vdkr-initramfs-create
#
# For x86_64:
#   MACHINE=qemux86-64 bitbake vdkr-initramfs-create
#
# Blobs are deployed to: tmp-vruntime-*/deploy/images/${MACHINE}/vdkr/
#
# To build the complete standalone tarball (recommended):
#   bitbake vcontainer-tarball
#
# ===========================================================================

SUMMARY = "Build QEMU blobs for vdkr"
DESCRIPTION = "Packages a tiny initramfs for switch_root and bundles the \
               rootfs.img from multiconfig build for vdkr."

# Set the runtime before including shared code
VCONTAINER_RUNTIME = "vdkr"

require vcontainer-initramfs-create.inc
