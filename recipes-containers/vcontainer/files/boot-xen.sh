#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# boot-xen.sh
# ===========================================================================
# Boot the packaged Xen dom0 image under QEMU and drop into the dom0 shell,
# where vxn runs and manages Xen PV DomU guests.
#
# This is the standalone-SDK (mode 2) launcher for vxn: instead of running
# Xen directly on the host hypervisor, Xen runs as a QEMU guest (KVM-
# accelerated) and vxn operates inside its dom0.  QEMU's interrupt emulation
# handles multi-vCPU cleanly, so this works where nested Xen-on-Hyper-V does
# not.  Intended for a Linux host or WSL2 with /dev/kvm.
#
# The dom0 image boots via SeaBIOS -> syslinux -> Xen multiboot (the .wic is
# self-contained).  dom0 is a NAT router for the DomU guests (XEN_DOM0_NETWORK
# = nat), so guests get addresses and outbound network with no host setup.
# ===========================================================================

set -euo pipefail

# --- locate ourselves and the SDK layout -----------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ARCH="${VXN_ARCH:-x86_64}"
VCPUS="${VXN_VCPUS:-4}"
MEM="${VXN_MEM:-4096}"
SSH_PORT="${VXN_SSH_PORT:-18022}"
EXTRA_QEMU="${VXN_QEMU_EXTRA:-}"

# --- pick the QEMU binary: prefer the SDK's nativesdk qemu, else host -------
QEMU=""
for cand in \
    "${SCRIPT_DIR}"/sysroots/*/usr/bin/qemu-system-"${ARCH}" \
    "$(command -v qemu-system-${ARCH} 2>/dev/null || true)"; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then QEMU="$cand"; break; fi
done
if [ -z "$QEMU" ]; then
    echo "error: qemu-system-${ARCH} not found (SDK sysroots or PATH)" >&2
    exit 1
fi

# --- locate the Xen dom0 wic blob for this arch ----------------------------
WIC="${VXN_IMAGE:-}"
if [ -z "$WIC" ]; then
    WIC="$(ls -1 "${SCRIPT_DIR}/vxn-blobs/${ARCH}"/*.wic 2>/dev/null | head -1 || true)"
fi
if [ -z "$WIC" ] || [ ! -f "$WIC" ]; then
    echo "error: Xen dom0 image (.wic) not found under vxn-blobs/${ARCH}/" >&2
    echo "       set VXN_IMAGE=/path/to/image.wic to override" >&2
    exit 1
fi

# --- KVM acceleration + CPU model ------------------------------------------
# Xen filters guest CPUID; -cpu host passes real features (AVX etc.) through so
# an x86-64-v3 dom0 does not hit illegal-instruction crashes.
ACCEL_OPTS=()
if [ -w /dev/kvm ]; then
    ACCEL_OPTS=(-enable-kvm -cpu host)
    echo "boot-xen: KVM acceleration enabled"
else
    echo "boot-xen: /dev/kvm not writable -- falling back to TCG (slow)."
    echo "boot-xen: in WSL2, set nestedVirtualization=true in .wslconfig."
    ACCEL_OPTS=(-cpu qemu64,+vmx)
fi

MACHINE_OPTS=()
if [ "$ARCH" = "x86_64" ]; then
    # q35, and disable the i8042 the Xen tune otherwise trips over.
    MACHINE_OPTS=(-machine q35,i8042=off)
fi

# --- networking: slirp NAT + forward host:SSH_PORT -> dom0:22 ---------------
# dom0 itself is a NAT router for the DomU guests (see XEN_DOM0_NETWORK=nat);
# this only wires dom0's uplink to the outside via slirp.
NET_OPTS=(
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22"
    -device "virtio-net-pci,netdev=net0"
)

echo "boot-xen: booting ${WIC##*/}  (${VCPUS} vCPU, ${MEM} MB)"
echo "boot-xen: dom0 SSH reachable at localhost:${SSH_PORT} once up"
echo "boot-xen: console follows; run 'vxn' inside dom0.  Ctrl-A X to quit QEMU."
echo

exec "$QEMU" \
    "${ACCEL_OPTS[@]}" \
    "${MACHINE_OPTS[@]}" \
    -smp "${VCPUS}" -m "${MEM}" \
    -drive "file=${WIC},format=raw,if=ide" \
    "${NET_OPTS[@]}" \
    -nographic -serial mon:stdio \
    ${EXTRA_QEMU}
