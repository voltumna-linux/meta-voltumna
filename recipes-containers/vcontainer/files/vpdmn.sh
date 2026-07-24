#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vpdmn: Podman-like interface for cross-architecture container operations
#
# This provides a familiar podman-like CLI that executes commands inside
# a QEMU-emulated environment with the target architecture's Podman.
#
# Command naming convention:
#   - Commands matching Podman's syntax/semantics use Podman's name (import, load, save, etc.)
#   - Extended commands with non-Podman behavior use 'v' prefix (vimport)

# Set runtime-specific parameters before sourcing common code
VCONTAINER_RUNTIME_NAME="vpdmn"
VCONTAINER_RUNTIME_CMD="podman"
VCONTAINER_RUNTIME_PREFIX="VPDMN"
VCONTAINER_IMPORT_TARGET="containers-storage:"
VCONTAINER_STATE_FILE="podman-state.img"
VCONTAINER_OTHER_PREFIX="VDKR"
VCONTAINER_VERSION="1.2.0"

# Auto-detect Xen if not explicitly set
if [ -z "${VCONTAINER_HYPERVISOR:-}" ]; then
    if command -v xl >/dev/null 2>&1; then
        export VCONTAINER_HYPERVISOR="xen"
    fi
fi

# Fall back to vxn blob dir on Dom0
if [ -z "${VPDMN_BLOB_DIR:-}" ] && [ -d "/usr/share/vxn" ]; then
    export VPDMN_BLOB_DIR="/usr/share/vxn"
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
