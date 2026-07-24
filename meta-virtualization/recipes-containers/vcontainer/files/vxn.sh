#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vxn: Docker CLI for Xen-based container execution
#
# This provides a familiar docker-like CLI that executes commands inside
# a Xen DomU guest with the target architecture's Docker.
#
# This is the Xen equivalent of vdkr (QEMU). It uses the same rootfs
# images and init scripts, but boots as a Xen PV guest instead of QEMU.
#
# Requires: Xen Dom0 with xl toolstack

# Set runtime-specific parameters before sourcing common code
VCONTAINER_RUNTIME_NAME="vxn"
VCONTAINER_RUNTIME_CMD="docker"
VCONTAINER_RUNTIME_PREFIX="VXN"
VCONTAINER_IMPORT_TARGET="docker-daemon:"
VCONTAINER_STATE_FILE="docker-state.img"
VCONTAINER_OTHER_PREFIX="VDKR"
VCONTAINER_VERSION="1.0.0"

# Select Xen hypervisor backend
export VCONTAINER_HYPERVISOR="xen"

# Set blob directory for target install (/usr/share/vxn has kernel, initramfs, rootfs)
# Use VXN_BLOB_DIR which _get_env_var() in vcontainer-common.sh will find
# via ${VCONTAINER_RUNTIME_PREFIX}_BLOB_DIR
if [ -z "${VXN_BLOB_DIR:-}" ]; then
    if [ -d "/usr/share/vxn" ]; then
        export VXN_BLOB_DIR="/usr/share/vxn"
    fi
fi

# Export runtime name so vrunner.sh (separate process) sees it
export VCONTAINER_RUNTIME_NAME

# Locate shared scripts - check script directory first, then /usr/lib/vxn
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
if [ -f "${SCRIPT_DIR}/vcontainer-common.sh" ]; then
    export VCONTAINER_LIBDIR="${SCRIPT_DIR}"
    source "${SCRIPT_DIR}/vcontainer-common.sh" "$@"
elif [ -f "/usr/lib/vxn/vcontainer-common.sh" ]; then
    export VCONTAINER_LIBDIR="/usr/lib/vxn"
    source "/usr/lib/vxn/vcontainer-common.sh" "$@"
else
    echo "Error: vcontainer-common.sh not found" >&2
    exit 1
fi
