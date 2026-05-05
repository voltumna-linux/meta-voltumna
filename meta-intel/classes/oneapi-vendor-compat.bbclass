# SPDX-License-Identifier: MIT
#
# oneapi-vendor-compat.bbclass
#
# The Intel oneAPI DPC++/C++ compiler binaries (icx, icpx) shipped by
# meta-intel as prebuilt installers have a fixed default ``-target`` triple
# baked into the LLVM driver. As of the 2025.3.x bundle the triple is
# ``x86_64-unknown-linux-gnu`` (LLVM's portable default); prior bundles used
# ``x86_64-oe-linux`` (matching the OpenEmbedded ``nodistro`` default of
# ``TARGET_VENDOR=oe``).
#
# Yocto distros set ``TARGET_VENDOR`` differently: poky uses ``poky``
# (TARGET_SYS=``x86_64-poky-linux``), nodistro uses ``oe``, etc. The result
# is a vendor-triple mismatch: icx looks for ``crtbeginS.o`` /
# ``bits/c++config.h`` and similar files under one triple while they are
# installed at another.
#
# Until Intel either ships per-vendor variants or the meta-intel oneAPI
# recipes patch the prebuilt binaries, this class installs a set of
# compatibility symlinks at rootfs time so every spelling of the multilib
# vendor triple resolves to the same files on the image. The class is a
# no-op when the native vendor triple already matches every alias.
#
# Usage: add to IMAGE_CLASSES in a distro / local config that consumes
# the Intel oneAPI compiler::
#
#     IMAGE_CLASSES += "oneapi-vendor-compat"
#

# Native triple as provided by Yocto for the target sysroot.
ONEAPI_VENDOR_TRIPLE_NATIVE ?= "${TARGET_SYS}"

# Aliases icx may resolve at runtime, in priority order:
#   - x86_64-unknown-linux-gnu : LLVM portable default (oneAPI 2025.x)
#   - x86_64-linux-gnu         : Debian/Ubuntu host triple (icx -v output)
#   - x86_64-oe-linux          : OE nodistro (oneAPI 2024.x)
ONEAPI_VENDOR_TRIPLE_ALIASES ?= " \
    ${TARGET_ARCH}-unknown-${TARGET_OS} \
    ${TARGET_ARCH}-${TARGET_OS}-gnu \
    ${TARGET_ARCH}-oe-${TARGET_OS} \
"

oneapi_vendor_compat_rootfs() {
    native="${ONEAPI_VENDOR_TRIPLE_NATIVE}"

    for alias in ${ONEAPI_VENDOR_TRIPLE_ALIASES}; do
        if [ "${alias}" = "${native}" ]; then
            continue
        fi

        # gcc multilib library tree (crt*.o, libgcc.a, etc).
        if [ -d "${IMAGE_ROOTFS}/usr/lib/${native}" ] && \
           [ ! -e "${IMAGE_ROOTFS}/usr/lib/${alias}" ]; then
            ln -s "${native}" \
                  "${IMAGE_ROOTFS}/usr/lib/${alias}"
        fi

        # multilib-aware C headers (e.g. asm/unistd_64.h).
        if [ -d "${IMAGE_ROOTFS}/usr/include/${native}" ] && \
           [ ! -e "${IMAGE_ROOTFS}/usr/include/${alias}" ]; then
            ln -s "${native}" \
                  "${IMAGE_ROOTFS}/usr/include/${alias}"
        fi

        # libstdc++ vendor-keyed bits (bits/c++config.h, ext/*.h).
        for cxxdir in "${IMAGE_ROOTFS}/usr/include/c++/"*/ ; do
            if [ -d "${cxxdir}/${native}" ] && \
               [ ! -e "${cxxdir}/${alias}" ]; then
                ln -s "${native}" \
                      "${cxxdir}/${alias}"
            fi
        done
    done
}

ROOTFS_POSTPROCESS_COMMAND:append = " oneapi_vendor_compat_rootfs;"
