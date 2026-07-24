#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
# SPDX-License-Identifier: MIT
#
# run-qemu-vm.sh — Launch a QEMU VM from OE build artifacts
#
# Finds the native QEMU binary, kernel, and rootfs from the build
# directory and launches a VM with optional socket networking for
# multi-node testing.
#
# Usage:
#   # Single VM (slirp network only)
#   ./run-qemu-vm.sh
#
#   # Server VM for multi-node (socket listen)
#   ./run-qemu-vm.sh --role server --socket-port 1234
#
#   # Agent VM for multi-node (socket connect)
#   ./run-qemu-vm.sh --role agent --socket-port 1234
#
#   # Custom settings
#   ./run-qemu-vm.sh --build-dir /path/to/build --machine qemuarm64 \
#                     --image container-image-host --memory 4096
#
# Environment variables (override defaults):
#   BUILD_DIR       Build directory (default: auto-detect from poky)
#   MACHINE         Target machine (default: qemux86-64)
#   IMAGE           Image name (default: container-image-host)
#   VM_MEMORY       VM memory in MB (default: 4096)
#   NO_KVM          Set to 1 to disable KVM (default: use KVM if available)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
MACHINE="${MACHINE:-qemux86-64}"
IMAGE="${IMAGE:-container-image-host}"
VM_MEMORY="${VM_MEMORY:-4096}"
ROLE=""
SOCKET_PORT=""
ROOTFS_PATH=""
NO_KVM="${NO_KVM:-0}"
EXTRA_CMDLINE=""

usage() {
    sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
    echo ""
    echo "Options:"
    echo "  --build-dir DIR     Build directory (default: auto-detect)"
    echo "  --machine MACHINE   Target machine (default: qemux86-64)"
    echo "  --image IMAGE       Image name (default: container-image-host)"
    echo "  --memory MB         VM memory in MB (default: 4096)"
    echo "  --role ROLE         'server' (socket listen) or 'agent' (socket connect)"
    echo "  --socket-port PORT  Socket port for multi-node networking"
    echo "  --rootfs PATH       Override rootfs path (e.g., for agent copy)"
    echo "  --append ARGS       Extra kernel cmdline arguments"
    echo "  --no-kvm            Disable KVM acceleration"
    echo "  --help              Show this help"
    exit 0
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --build-dir)    BUILD_DIR="$2"; shift 2 ;;
        --machine)      MACHINE="$2"; shift 2 ;;
        --image)        IMAGE="$2"; shift 2 ;;
        --memory)       VM_MEMORY="$2"; shift 2 ;;
        --role)         ROLE="$2"; shift 2 ;;
        --socket-port)  SOCKET_PORT="$2"; shift 2 ;;
        --rootfs)       ROOTFS_PATH="$2"; shift 2 ;;
        --append)       EXTRA_CMDLINE="$2"; shift 2 ;;
        --no-kvm)       NO_KVM=1; shift ;;
        --help|-h)      usage ;;
        *)              echo "Unknown option: $1"; usage ;;
    esac
done

# Auto-detect build directory
if [ -z "$BUILD_DIR" ]; then
    # Walk up from layer to find poky, then build
    POKY_DIR="$(cd "$LAYER_DIR/.." && pwd)"
    if [ -d "$POKY_DIR/build" ]; then
        BUILD_DIR="$POKY_DIR/build"
    else
        echo "ERROR: Cannot auto-detect build directory. Use --build-dir."
        exit 1
    fi
fi

DEPLOY_DIR="$BUILD_DIR/tmp/deploy/images/$MACHINE"

# Architecture-specific settings
case "$MACHINE" in
    qemux86-64)
        QEMU_BIN="qemu-system-x86_64"
        QEMU_MACHINE="-M q35"
        QEMU_CPU_KVM="-cpu host"
        QEMU_CPU_TCG="-cpu Skylake-Client"
        KERNEL_NAME="bzImage"
        CONSOLE="ttyS0"
        ROOTDEV="/dev/vda"
        ;;
    qemuarm64)
        QEMU_BIN="qemu-system-aarch64"
        QEMU_MACHINE="-M virt"
        QEMU_CPU_KVM="-cpu host"
        QEMU_CPU_TCG="-cpu cortex-a57"
        KERNEL_NAME="Image"
        CONSOLE="ttyAMA0"
        ROOTDEV="/dev/vda"
        ;;
    *)
        echo "ERROR: Unsupported machine '$MACHINE'. Supported: qemux86-64, qemuarm64"
        exit 1
        ;;
esac

# Find native QEMU binary
NATIVE_BINDIR="$BUILD_DIR/tmp/sysroots-components/x86_64/qemu-system-native/usr/bin"
if [ -x "$NATIVE_BINDIR/$QEMU_BIN" ]; then
    QEMU_PATH="$NATIVE_BINDIR/$QEMU_BIN"
elif command -v "$QEMU_BIN" >/dev/null 2>&1; then
    QEMU_PATH="$(command -v "$QEMU_BIN")"
else
    echo "ERROR: $QEMU_BIN not found in $NATIVE_BINDIR or PATH"
    exit 1
fi

# Set LD_LIBRARY_PATH for native QEMU shared libraries
NATIVE_LIBDIRS=""
for libdir in "$BUILD_DIR"/tmp/sysroots-components/x86_64/*/usr/lib; do
    [ -d "$libdir" ] && NATIVE_LIBDIRS="${NATIVE_LIBDIRS:+$NATIVE_LIBDIRS:}$libdir"
done
export LD_LIBRARY_PATH="${NATIVE_LIBDIRS}:${LD_LIBRARY_PATH:-}"

# Find kernel
KERNEL="$DEPLOY_DIR/$KERNEL_NAME"
if [ ! -f "$KERNEL" ]; then
    echo "ERROR: Kernel not found: $KERNEL"
    exit 1
fi

# Find or use provided rootfs
if [ -n "$ROOTFS_PATH" ]; then
    ROOTFS="$ROOTFS_PATH"
else
    ROOTFS=$(ls -t "$DEPLOY_DIR/${IMAGE}-${MACHINE}".rootfs.ext4 2>/dev/null | head -1)
    if [ -z "$ROOTFS" ]; then
        echo "ERROR: No ext4 rootfs found for $IMAGE in $DEPLOY_DIR"
        exit 1
    fi
fi

if [ ! -f "$ROOTFS" ]; then
    echo "ERROR: Rootfs not found: $ROOTFS"
    exit 1
fi

# KVM detection
KVM_FLAG=""
QEMU_CPU="$QEMU_CPU_TCG"
if [ "$NO_KVM" != "1" ]; then
    HOST_ARCH=$(uname -m)
    case "$MACHINE" in
        qemux86-64) TARGET_ARCH="x86_64" ;;
        qemuarm64)  TARGET_ARCH="aarch64" ;;
    esac
    if [ "$HOST_ARCH" = "$TARGET_ARCH" ] && [ -w /dev/kvm ]; then
        KVM_FLAG="-enable-kvm"
        QEMU_CPU="$QEMU_CPU_KVM"
        echo "KVM acceleration enabled"
    else
        echo "KVM not available, using TCG emulation"
    fi
fi

# Build socket networking args
SOCKET_ARGS=""
if [ -n "$ROLE" ] && [ -n "$SOCKET_PORT" ]; then
    case "$ROLE" in
        server)
            SOCKET_ARGS="-netdev socket,id=vlan0,listen=:${SOCKET_PORT} -device virtio-net-pci,netdev=vlan0"
            echo "Socket networking: listening on port $SOCKET_PORT (server)"
            ;;
        agent)
            SOCKET_ARGS="-netdev socket,id=vlan0,connect=127.0.0.1:${SOCKET_PORT} -device virtio-net-pci,netdev=vlan0"
            echo "Socket networking: connecting to port $SOCKET_PORT (agent)"
            ;;
        *)
            echo "ERROR: --role must be 'server' or 'agent'"
            exit 1
            ;;
    esac
fi

echo "QEMU:    $QEMU_PATH"
echo "Kernel:  $KERNEL"
echo "Rootfs:  $ROOTFS"
echo "Machine: $MACHINE"
echo "Memory:  ${VM_MEMORY}M"
echo ""

exec "$QEMU_PATH" \
    $QEMU_MACHINE $QEMU_CPU $KVM_FLAG \
    -m "$VM_MEMORY" -smp 2 -nographic \
    -kernel "$KERNEL" \
    -drive "file=$ROOTFS,if=virtio,format=raw" \
    -append "root=$ROOTDEV rw console=$CONSOLE ip=dhcp${EXTRA_CMDLINE:+ $EXTRA_CMDLINE}" \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
    $SOCKET_ARGS
