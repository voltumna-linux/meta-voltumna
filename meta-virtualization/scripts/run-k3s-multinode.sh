#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
# SPDX-License-Identifier: MIT
#
# run-k3s-multinode.sh — Launch a k3s multi-node cluster in QEMU
#
# Starts two VMs connected via QEMU socket networking:
#   - Server VM: k3s server on 192.168.50.1 (default role)
#   - Agent VM:  k3s agent on 192.168.50.2 (configured via kernel cmdline)
#
# The same container-image-host image is used for both roles.
# The k3s-role-setup.service reads k3s.role= from the kernel cmdline
# and configures the appropriate k3s service automatically.
#
# Prerequisites:
#   - Build with k3s profile:
#       require conf/distro/include/meta-virt-host.conf
#       require conf/distro/include/container-host-k3s.conf
#       MACHINE = "qemux86-64"
#       bitbake container-image-host
#
# Usage:
#   # Start the server (Terminal 1)
#   ./run-k3s-multinode.sh server
#
#   # Start the agent (Terminal 2) — requires server token
#   ./run-k3s-multinode.sh agent --token <TOKEN>
#
#   # Get the token from the server VM:
#   cat /var/lib/rancher/k3s/server/node-token
#
#   # Verify on server VM:
#   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
#   kubectl get nodes    # should show 2 nodes Ready
#
# Options:
#   --port PORT          Socket port (default: 1234, must match both VMs)
#   --token TOKEN        Join token (required for agent)
#   --build-dir DIR      Build directory
#   --machine MACHINE    Target machine (default: qemux86-64)
#   --server-ip IP       Server IP (default: 192.168.50.1)
#   --agent-ip IP        Agent IP (default: 192.168.50.2)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLE="${1:-}"
shift 2>/dev/null || true

SOCKET_PORT="1234"
BUILD_DIR=""
MACHINE="${MACHINE:-qemux86-64}"
TOKEN=""
SERVER_IP="192.168.50.1"
AGENT_IP="192.168.50.2"

while [ $# -gt 0 ]; do
    case "$1" in
        --port)       SOCKET_PORT="$2"; shift 2 ;;
        --build-dir)  BUILD_DIR="$2"; shift 2 ;;
        --machine)    MACHINE="$2"; shift 2 ;;
        --token)      TOKEN="$2"; shift 2 ;;
        --server-ip)  SERVER_IP="$2"; shift 2 ;;
        --agent-ip)   AGENT_IP="$2"; shift 2 ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$ROLE" ] || { [ "$ROLE" != "server" ] && [ "$ROLE" != "agent" ]; }; then
    echo "Usage: $0 <server|agent> [options]"
    echo ""
    echo "Start the server first, then the agent with the join token."
    echo ""
    echo "  Terminal 1:  $0 server"
    echo "  Server VM:   cat /var/lib/rancher/k3s/server/node-token"
    echo "  Terminal 2:  $0 agent --token <TOKEN>"
    echo "  Server VM:   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
    echo "               kubectl get nodes"
    echo ""
    echo "Options:"
    echo "  --port PORT          Socket port (default: 1234)"
    echo "  --token TOKEN        Join token (required for agent)"
    echo "  --build-dir DIR      Build directory"
    echo "  --machine MACHINE    Target machine (default: qemux86-64)"
    echo "  --server-ip IP       Server IP (default: 192.168.50.1)"
    echo "  --agent-ip IP        Agent IP (default: 192.168.50.2)"
    exit 1
fi

# Build args for run-qemu-vm.sh
EXTRA_ARGS="--role $ROLE --socket-port $SOCKET_PORT"
[ -n "$BUILD_DIR" ] && EXTRA_ARGS="$EXTRA_ARGS --build-dir $BUILD_DIR"
EXTRA_ARGS="$EXTRA_ARGS --machine $MACHINE"

# Build kernel cmdline for k3s role configuration
case "$ROLE" in
    server)
        KCMD="k3s.role=server k3s.node-ip=$SERVER_IP"
        echo "=== K3s Server ==="
        echo "After boot, get the join token:"
        echo "  cat /var/lib/rancher/k3s/server/node-token"
        echo ""
        echo "Then start the agent in another terminal:"
        echo "  $0 agent --token <TOKEN>"
        echo ""
        ;;

    agent)
        if [ -z "$TOKEN" ]; then
            echo "ERROR: --token is required for agent mode"
            echo "Get it from the server VM: cat /var/lib/rancher/k3s/server/node-token"
            exit 1
        fi
        KCMD="k3s.role=agent k3s.server=$SERVER_IP k3s.token=$TOKEN k3s.node-name=k3s-agent k3s.node-ip=$AGENT_IP"
        echo "=== K3s Agent ==="
        echo "Joining server at $SERVER_IP"
        echo ""
        ;;
esac

EXTRA_ARGS="$EXTRA_ARGS --append \"$KCMD\""

# Agent needs its own rootfs copy
if [ "$ROLE" = "agent" ]; then
    POKY_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
    _BUILD_DIR="${BUILD_DIR:-$POKY_DIR/build}"
    DEPLOY_DIR="$_BUILD_DIR/tmp/deploy/images/$MACHINE"
    IMAGE="${IMAGE:-container-image-host}"
    ORIG_ROOTFS=$(ls -t "$DEPLOY_DIR/${IMAGE}-${MACHINE}".rootfs.ext4 2>/dev/null | head -1)

    if [ -z "$ORIG_ROOTFS" ]; then
        echo "ERROR: No rootfs found in $DEPLOY_DIR"
        exit 1
    fi

    AGENT_ROOTFS="/tmp/k3s-agent-rootfs-$$.ext4"
    echo "Copying rootfs for agent VM: $ORIG_ROOTFS -> $AGENT_ROOTFS"
    cp "$ORIG_ROOTFS" "$AGENT_ROOTFS"
    EXTRA_ARGS="$EXTRA_ARGS --rootfs $AGENT_ROOTFS"

    trap "rm -f '$AGENT_ROOTFS'" EXIT
fi

eval exec "$SCRIPT_DIR/run-qemu-vm.sh" $EXTRA_ARGS
