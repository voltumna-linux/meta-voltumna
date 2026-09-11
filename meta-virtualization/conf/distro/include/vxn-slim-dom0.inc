# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vxn-slim-dom0.inc -- opt-in slimming for the vxn dom0 image (SDK distribution)
# ============================================================================
# Required ONLY from the vxn multiconfig, and only when VXN_SLIM_DOM0 = "1".
# A standard xen-image-minimal build (main config) never parses this file, so
# ordinary Xen root filesystems are completely unaffected.
#
# The vxn dom0 boots PV/PVH DomUs (vrunner-backend-xen.sh sets xen_type=pv) and
# never invokes qemu at runtime, so three things xen-tools drags in are dead
# weight -- together ~530MB of the ~1.2GB dom0 rootfs:
#
#   - qemu-system-i386        the HVM device model (PV guests need no qemu-dm)
#   - qemu-firmware           foreign-arch EDK2 (arm/aarch64/riscv/loongarch)
#   - qemu + its GL chain     virglrenderer -> mesa/gallium -> LLVM (headless
#                             dom0 needs no GL; the chain's only consumer is qemu)
#
# Dropping them keeps every vxn runtime path intact: provision (skopeo),
# `xl create` PV DomUs, containerd, and the bundled guest rootfs.
#
# What is given up: qemu is Xen's DEVICE MODEL -- it emulates devices for HVM
# guests (and for PV guests that want emulated hardware). vxn runs PV/PVH DomUs
# with paravirtual devices only, so it is unused today. If a future vxn DomU
# needs device virtualization (an HVM guest, or an emulated device on a PV
# guest), qemu must come back: set VXN_SLIM_DOM0 = "0" (before this file is
# required) to build the full dom0. This trim is a deliberate, reversible
# size-for-capability trade, not a permanent removal.

# Under `vmsep`, meta-virt splits qemu (recipes-devtools/qemu/qemu-package-split.inc)
# into qemu (base) + qemu-<arch> + qemu-system-i386 + qemu-firmware, and every
# split sub-package does `RDEPENDS += ${PN}` -- so pulling ANY of them re-pulls
# the base `qemu`. It has to be cut from all three angles:

# 1. Direct hard IMAGE_INSTALL: xen-image-minimal.bb lists the base `qemu` in
#    IMAGE_INSTALL. Remove it here (scoped to this multiconfig; the recipe is
#    untouched, so standard xen-image-minimal builds still ship qemu).
IMAGE_INSTALL:remove = "qemu"

# 2. Hard RDEPENDS: xen-tools RDEPENDS ${QEMU_SYSTEM} ${QEMU_FIRMWARE} via
#    QEMU_SYSTEM_RDEPENDS, and each of those split pkgs RDEPENDS the base qemu.
#    Empty the source vars (scoped to xen-tools) so neither -- nor the base qemu
#    behind them -- is pulled.
QEMU_SYSTEM:pn-xen-tools   = ""
QEMU_FIRMWARE:pn-xen-tools = ""

# 3. Soft RRECOMMENDS: xen-tools RRECOMMENDS qemu (+ vmsep qemu-x86_64/qemu-i386).
#    Now that nothing hard-requires them, drop the weak deps too; this also
#    removes the GL rendering chain (virglrenderer/mesa/gallium/LLVM), whose only
#    consumer is qemu.
BAD_RECOMMENDATIONS:append = " qemu qemu-x86_64 qemu-i386"
