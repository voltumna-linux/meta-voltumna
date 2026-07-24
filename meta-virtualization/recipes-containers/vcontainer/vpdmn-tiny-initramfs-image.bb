# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vpdmn-tiny-initramfs-image.bb - Tiny initramfs for vpdmn
#
# Build with:
#   bitbake mc:vruntime-aarch64:vpdmn-tiny-initramfs-image
#   bitbake mc:vruntime-x86-64:vpdmn-tiny-initramfs-image
#
# Output: ${DEPLOY_DIR_IMAGE}/vpdmn-tiny-initramfs-image-${MACHINE}.cpio.gz

require vcontainer-tiny-initramfs-image.inc
