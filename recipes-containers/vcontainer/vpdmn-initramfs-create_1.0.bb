# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vpdmn-initramfs-create_1.0.bb
# ===========================================================================
# Builds QEMU boot blobs for vpdmn (Podman CLI)
# ===========================================================================
#
# This recipe packages the boot blobs for vpdmn:
# - A tiny initramfs with just busybox for switch_root
# - The rootfs.img squashfs image with Podman (built via multiconfig)
# - The kernel
#
# Boot flow:
#   QEMU boots kernel + tiny initramfs
#   -> preinit mounts rootfs.img from /dev/vda
#   -> switch_root into rootfs.img
#   -> vpdmn-init.sh runs with a real root filesystem
#   -> Podman executes container commands
#
# ===========================================================================
# BUILD INSTRUCTIONS
# ===========================================================================
#
# For aarch64 (multiconfig dependency is automatic):
#   MACHINE=qemuarm64 bitbake vpdmn-initramfs-create
#
# For x86_64:
#   MACHINE=qemux86-64 bitbake vpdmn-initramfs-create
#
# Blobs are deployed to: tmp-vruntime-*/deploy/images/${MACHINE}/vpdmn/
#
# To build the complete standalone tarball (recommended):
#   bitbake vcontainer-tarball
#
# ===========================================================================

SUMMARY = "Build QEMU blobs for vpdmn"
DESCRIPTION = "Packages a tiny initramfs for switch_root and bundles the \
               rootfs.img with Podman from multiconfig build for vpdmn."

# Set the runtime before including shared code
VCONTAINER_RUNTIME = "vpdmn"

require vcontainer-initramfs-create.inc
