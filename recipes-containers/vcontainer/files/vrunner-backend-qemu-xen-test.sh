#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vrunner-backend-qemu-xen-test.sh -- L1 architectural test for phase-3 vxn
# ===========================================================================
# Drives vrunner-backend-qemu-xen.sh's hv_* functions in the exact order
# vrunner.sh's daemon-start path calls them, with VXN_DRY_RUN=1 so the backend
# composes the QEMU command line but does NOT launch anything.  Asserts the
# command is correct -- boots the wic (no -kernel/-append), wires the
# virtio-serial command channel + QMP, forwards ports, honours VXN_VCPUS/MEM,
# and picks the right -cpu for KVM vs TCG.
#
# Instant, no VM, no Xen.  Usage:  bash vrunner-backend-qemu-xen-test.sh
# Exit 0 = all pass.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="${1:-$SCRIPT_DIR/vrunner-backend-qemu-xen.sh}"
[ -f "$BACKEND" ] || { echo "FAIL: backend not found: $BACKEND"; exit 1; }

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# Fake SDK blob layout: a stand-in dom0 wic.
mkdir -p "$TMPD/blobs/x86_64"
: > "$TMPD/blobs/x86_64/xen-dom0.wic"

# Minimal stubs for the vrunner-provided environment the backend reads.
log() { :; }                       # vrunner's logger (LEVEL, msg)
TARGET_ARCH="x86_64"
BLOB_DIR="$TMPD/blobs"
STAGING_BINDIR_NATIVE=""
NETWORK="true"
PORT_FORWARDS=("8080:80/tcp")
DAEMON_SOCKET_DIR="$TMPD/daemon"
DAEMON_SOCKET="$DAEMON_SOCKET_DIR/daemon.sock"
mkdir -p "$DAEMON_SOCKET_DIR"
export VXN_VCPUS=3 VXN_MEM=3072 VXN_DRY_RUN=1

# shellcheck disable=SC1090
source "$BACKEND"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; echo "        $2"; }
has()    { case "$CMD" in *"$1"*) ok "$2" ;; *) bad "$2" "missing: $1"$'\n'"        cmd: $CMD" ;; esac; }
hasnot() { case "$CMD" in *"$1"*) bad "$2" "unexpected: $1"$'\n'"        cmd: $CMD" ;; *) ok "$2" ;; esac; }

# Replicate vrunner.sh's daemon-start call order and compose the command.
compose() {
    HV_OPTS=""; HV_DISK_OPTS=""; HV_NET_OPTS=""; HV_DAEMON_OPTS=""; HV_VM_PID=""
    hv_setup_arch
    hv_check_accel
    hv_build_disk_opts
    hv_build_network_opts
    hv_build_vm_cmd
    hv_build_9p_opts "$DAEMON_SOCKET_DIR/share" "vxn_share"
    hv_build_daemon_opts
    HV_OPTS="$HV_OPTS $HV_DAEMON_OPTS"        # vrunner.sh:1471
    local logf="$TMPD/cmd.log"
    hv_start_vm_background "ignored_kernel_append" "$logf" ""
    CMD="$(cat "$logf")"
}

echo "L1 qemu-xen backend test  (backend: $BACKEND)"

# ---- Scenario A: forced TCG (deterministic on any host) -------------------
echo "-- scenario A: TCG (--no-kvm) --"
DISABLE_KVM="true"
compose
has   "-machine q35,i8042=off"          "q35 + i8042=off machine"
has   "-cpu qemu64,+vmx"                 "TCG cpu model (nested-virt capable)"
hasnot "-enable-kvm"                     "no -enable-kvm under TCG"
has   "xen-dom0.wic,format=raw,if=ide"   "boots dom0 wic as IDE disk"
hasnot "-kernel"                         "no -kernel (firmware/wic boot)"
hasnot "-initrd"                         "no -initrd"
hasnot "-append"                         "no -append (cmdline baked in wic)"
has   "-smp 3"                           "VXN_VCPUS honoured (-smp 3)"
has   "-m 3072"                          "VXN_MEM honoured (-m 3072)"
has   "-chardev socket,id=vdkr,path=$DAEMON_SOCKET,server=on,wait=off" "vdkr command-channel chardev on daemon socket"
has   "-device virtserialport,chardev=vdkr,name=vdkr" "virtserialport name=vdkr"
has   "-qmp unix:$DAEMON_SOCKET_DIR/qmp.sock" "QMP control socket"
has   "hostfwd=tcp::8080-:8080"          "port forward hostfwd wired"
has   "-virtfs local,path=$DAEMON_SOCKET_DIR/share" "9p share attached"
has   "-no-reboot"                       "-no-reboot set"

# ---- Scenario B: real KVM (only if /dev/kvm is writable) ------------------
if [ -w /dev/kvm ]; then
    echo "-- scenario B: KVM (/dev/kvm writable) --"
    DISABLE_KVM="false"
    compose
    has    "-enable-kvm"                  "KVM: -enable-kvm present"
    has    "-cpu host"                    "KVM: -cpu host (pass real CPUID/AVX)"
    hasnot "-cpu qemu64"                  "KVM: TCG cpu model not used"
else
    echo "-- scenario B: SKIP (/dev/kvm not writable) --"
fi

# ---- Scenario C: VXN_IMAGE override ---------------------------------------
echo "-- scenario C: VXN_IMAGE override --"
: > "$TMPD/custom.wic"
DISABLE_KVM="true"
VXN_IMAGE="$TMPD/custom.wic" compose
has "file=$TMPD/custom.wic" "VXN_IMAGE override selects custom wic"

echo
echo "L1 result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
