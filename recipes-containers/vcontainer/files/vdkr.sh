#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vdkr: Docker-like interface for cross-architecture container operations
#
# This provides a familiar docker-like CLI that executes commands inside
# a QEMU-emulated environment with the target architecture's Docker.
#
# Command naming convention:
#   - Commands matching Docker's syntax/semantics use Docker's name (import, load, save, etc.)
#   - Extended commands with non-Docker behavior use 'v' prefix (vimport)

# Set runtime-specific parameters before sourcing common code
VCONTAINER_RUNTIME_NAME="vdkr"
VCONTAINER_RUNTIME_CMD="docker"
VCONTAINER_RUNTIME_PREFIX="VDKR"
VCONTAINER_IMPORT_TARGET="docker-daemon:"
VCONTAINER_STATE_FILE="docker-state.img"
VCONTAINER_OTHER_PREFIX="VPDMN"
VCONTAINER_VERSION="3.4.0"

# Auto-detect Xen if not explicitly set
if [ -z "${VCONTAINER_HYPERVISOR:-}" ]; then
    if command -v xl >/dev/null 2>&1; then
        export VCONTAINER_HYPERVISOR="xen"
    fi
fi

# Fall back to vxn blob dir on Dom0
if [ -z "${VDKR_BLOB_DIR:-}" ] && [ -d "/usr/share/vxn" ]; then
    export VDKR_BLOB_DIR="/usr/share/vxn"
fi

# Two-phase lib lookup: script dir (dev), then /usr/lib/vxn (target)
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
