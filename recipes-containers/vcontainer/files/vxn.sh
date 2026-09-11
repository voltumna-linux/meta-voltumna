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

# Locate shared scripts early (needed for blob-dir / backend detection below)
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

# Blob directory (found by _get_env_var() as ${VCONTAINER_RUNTIME_PREFIX}_BLOB_DIR):
#   - SDK bundle (mode 1, host-side): vxn-blobs/ sits beside this wrapper and
#     holds the Xen dom0 *.wic image(s).
#   - dom0 target (mode xen, in-Xen): /usr/share/vxn holds kernel/initramfs/rootfs.
if [ -z "${VXN_BLOB_DIR:-}" ]; then
    if [ -d "${SCRIPT_DIR}/vxn-blobs" ]; then
        export VXN_BLOB_DIR="${SCRIPT_DIR}/vxn-blobs"
    elif [ -d "/usr/share/vxn" ]; then
        export VXN_BLOB_DIR="/usr/share/vxn"
    fi
fi

# Hypervisor backend auto-selection (override by pre-setting VCONTAINER_HYPERVISOR):
#   - a Xen dom0 *.wic present in the blob dir -> boot it under QEMU via the
#     qemu-xen backend. This is the transparent host-side path (WSL/Linux): the
#     host runs `vxn`, a Xen dom0 boots as a KVM guest, and commands are proxied
#     into dom0 -- the vdkr/vpdmn UX, but the VM is a Xen dom0.
#   - otherwise -> drive the real xl toolstack (xen), i.e. running inside an
#     actual Xen dom0 where vxn is the installed target package.
if [ -z "${VCONTAINER_HYPERVISOR:-}" ]; then
    if ls "${VXN_BLOB_DIR:-/nonexistent}"/*/*.wic >/dev/null 2>&1; then
        export VCONTAINER_HYPERVISOR="qemu-xen"
    else
        export VCONTAINER_HYPERVISOR="xen"
    fi
fi

# In qemu-xen mode the host is a thin transport: it boots the dom0 wic and
# relays the command into dom0, where vxn's OWN front end does the real work
# (skopeo pull + xl create DomU). So the command dispatched into dom0 must be
# "vxn <verb> ..." -- dom0's native front end -- NOT the internal "docker
# <verb>" string vxn builds for the in-process Xen backend to parse. The
# responder shell-executes what it receives, and dom0's "docker" is podman;
# dispatching "docker run" would hit podman/netavark instead of vxn/xl. Keeping
# it "vxn ..." stays entirely inside vxn's front end -- no container engine in
# the path. (The real in-dom0 "xen" backend keeps the "docker" internal form,
# which it parses rather than executes.)
if [ "$VCONTAINER_HYPERVISOR" = "qemu-xen" ]; then
    VCONTAINER_RUNTIME_CMD="vxn"
fi

# Export runtime name so vrunner.sh (separate process) sees it
export VCONTAINER_RUNTIME_NAME

# Source shared code (SDK dir first, then target libdir)
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
