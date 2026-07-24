# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vdkr-tiny-initramfs-image.bb - Tiny initramfs for vdkr
#
# Build with:
#   bitbake mc:vruntime-aarch64:vdkr-tiny-initramfs-image
#   bitbake mc:vruntime-x86-64:vdkr-tiny-initramfs-image
#
# Output: ${DEPLOY_DIR_IMAGE}/vdkr-tiny-initramfs-image-${MACHINE}.cpio.gz

require vcontainer-tiny-initramfs-image.inc
