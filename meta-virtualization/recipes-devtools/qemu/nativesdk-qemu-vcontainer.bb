# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# Minimal QEMU variant for vcontainer tools (vdkr/vpdmn)
#
# This recipe provides a stripped-down nativesdk QEMU without OpenGL/SDL
# dependencies, avoiding the mesa -> llvm -> clang build chain.
#
# This is separate from the main nativesdk-qemu to avoid affecting other
# users who may need OpenGL support in their SDK QEMU.
#
# VERSION TRACKING: This recipe automatically discovers the QEMU version
# from oe-core, so no updates are needed when oe-core bumps QEMU.

SUMMARY = "Minimal QEMU for vcontainer tools"
DESCRIPTION = "QEMU built without OpenGL/virglrenderer for use in vcontainer \
               standalone tarballs. Avoids pulling in mesa/llvm/clang."

# Dynamically discover QEMU version from oe-core (same pattern as busybox-initrd.bb)
def get_qemu_pv(d):
    import os
    import re
    corebase = d.getVar('COREBASE')
    qemu_dir = os.path.join(corebase, 'meta', 'recipes-devtools', 'qemu')
    if os.path.isdir(qemu_dir):
        re_bb_name = re.compile(r"^qemu_([0-9.]+)\.bb$")
        for bb_file in os.listdir(qemu_dir):
            result = re_bb_name.match(bb_file)
            if result:
                return result.group(1)
    bb.fatal("Cannot find qemu recipe in %s" % qemu_dir)

PV := "${@get_qemu_pv(d)}"

# Point to oe-core qemu files directory for patches and support files
FILESEXTRAPATHS:prepend := "${COREBASE}/meta/recipes-devtools/qemu/qemu:"

# Use the same base as oe-core qemu
require recipes-devtools/qemu/qemu.inc

# Pull in the main recipe's dependencies and settings
DEPENDS += "glib-2.0 zlib pixman"
DEPENDS:append:libc-musl = " libucontext"

# Inherit nativesdk explicitly (not via BBCLASSEXTEND)
inherit nativesdk

# Target list for nativesdk (cross-prefix is already set by qemu.inc for class-nativesdk)
EXTRA_OECONF:append = " --target-list=${@get_qemu_target_list(d)}"

# Minimal PACKAGECONFIG - no opengl, no sdl, no virglrenderer
# This avoids mesa -> llvm -> clang dependency chain
# virtfs is needed for volume mounts (-v host:container)
PACKAGECONFIG = "fdt kvm pie slirp virtfs"

# Build only the QEMU system targets for the architectures the SDK actually
# bundles (VCONTAINER_ARCHITECTURES). An x86_64-only SDK then drops
# qemu-system-aarch64 (~33MB). Fallback default matches the tarball's.
VCONTAINER_ARCHITECTURES ??= "x86_64 aarch64"
QEMU_TARGETS = "${VCONTAINER_ARCHITECTURES}"

# EDK2 firmware for architectures this SDK does not target is dead weight
# (~290MB). riscv, loongarch and 32-bit arm are never vcontainer targets, so
# always drop them; aarch64 firmware is kept only when the SDK actually builds
# for aarch64 (VCONTAINER_ARCHITECTURES) -- so a future ARM-host SDK keeps it.
# x86_64 OVMF is always kept (Xen dom0 XEN_BOOT_MODE=efi).
# NOTE: arch-driven, NOT vxn-specific -- this qemu is the SDK's host qemu for
# ANY vcontainer build (vdkr/vpdmn boot the vruntime VMs; vxn boots the dom0).
do_install:append() {
    find ${D} -type f \( -name 'edk2-riscv-*.fd' -o -name 'edk2-loongarch64-*.fd' \
        -o -name 'edk2-arm-*.fd' \) -delete 2>/dev/null || true
    if ! echo "${VCONTAINER_ARCHITECTURES}" | grep -qw aarch64; then
        find ${D} -type f -name 'edk2-aarch64-*.fd' -delete 2>/dev/null || true
    fi
}

# QEMU's configure doesn't support --disable-static, so disable it
DISABLE_STATIC = ""

# Ensure proper naming
BPN = "qemu"
