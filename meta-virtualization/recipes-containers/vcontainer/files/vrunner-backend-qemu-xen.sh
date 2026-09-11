#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vrunner-backend-qemu-xen.sh
# QEMU-hosted-Xen hypervisor backend for vrunner.sh
#
# Sourced by vrunner.sh when VCONTAINER_HYPERVISOR=qemu-xen.
#
# Unlike the plain "qemu" backend (which boots a Linux kernel+initramfs
# directly as the container VM), this backend boots a *Xen dom0* image (a
# self-contained .wic booted via SeaBIOS -> syslinux -> Xen multiboot) as a
# KVM-accelerated QEMU guest.  vxn runs inside that dom0 and turns each
# `docker run` into a Xen PV DomU.  This is the transparent host-side path
# (mode 1) for vxn -- the same UX as vdkr/vpdmn, but the VM is a Xen dom0.
#
# It exists because nested Xen-on-Hyper-V dies on multi-vCPU interrupt
# delivery (Client-Hyper-V-on-AMD limitation); QEMU's interrupt emulation
# handles SMP cleanly, so `vxn` works under WSL2/QEMU where direct nesting
# does not.  See agent-files/meta-virt-containers/vxn-windows.md.
#
# Key differences from vrunner-backend-qemu.sh:
#   * boots a .wic disk via the firmware bootloader -- NO -kernel/-initrd,
#     and therefore NO -append (the Xen+dom0 cmdline is baked into the wic).
#   * -machine q35,i8042=off  and  -cpu host (KVM) -- Xen filters guest CPUID,
#     so real features must pass through (x86-64-v3 dom0 else traps on AVX).
#   * disk is the dom0 wic (if=ide); Xen dom0 owns all guest storage, so no
#     rootfs / state / input disks are attached.
#   * command channel + readiness are the SAME as the qemu backend: a
#     virtio-serial port (name=vdkr) bridged to $DAEMON_SOCKET, answered in
#     dom0 by vxn-command-channel.sh (a systemd service), speaking the marker
#     protocol daemon_send() already understands.  So the host side is reused
#     unchanged and readiness uses the generic socket ===PING===/===PONG===.

# ============================================================================
# Architecture Setup
# ============================================================================

hv_setup_arch() {
    # Resources for dom0-hosted Xen.  VXN_VCPUS/VXN_MEM default higher than the
    # plain qemu backend because dom0 has to host PV DomU guests on top of its
    # own services (docker, dnsmasq, NAT).
    XEN_VCPUS="${VXN_VCPUS:-4}"
    XEN_MEM="${VXN_MEM:-4096}"

    case "$TARGET_ARCH" in
        x86_64)
            HV_CMD="qemu-system-x86_64"
            # q35 + disable i8042 (the Xen x86-64-v3 tune otherwise trips on it).
            HV_MACHINE="-machine q35,i8042=off -cpu qemu64,+vmx"
            HV_CONSOLE="ttyS0"
            ;;
        *)
            log "ERROR" "qemu-xen backend supports x86_64 only (got: $TARGET_ARCH)"
            log "ERROR" "Xen dom0 is not built for aarch64 in the vxn multiconfig yet"
            exit 1
            ;;
    esac

    # Locate the Xen dom0 wic blob.  VXN_IMAGE overrides; otherwise prefer the
    # canonical name the SDK tarball installs, then any *.wic in the arch dir.
    WIC_IMAGE="${VXN_IMAGE:-}"
    if [ -z "$WIC_IMAGE" ]; then
        if [ -f "$BLOB_DIR/$TARGET_ARCH/xen-dom0.wic" ]; then
            WIC_IMAGE="$BLOB_DIR/$TARGET_ARCH/xen-dom0.wic"
        else
            WIC_IMAGE="$(ls -1 "$BLOB_DIR/$TARGET_ARCH"/*.wic 2>/dev/null | head -1 || true)"
        fi
    fi
    if [ -z "$WIC_IMAGE" ] || [ ! -f "$WIC_IMAGE" ]; then
        log "ERROR" "Xen dom0 image (.wic) not found under $BLOB_DIR/$TARGET_ARCH/"
        log "ERROR" "set VXN_IMAGE=/path/to/image.wic to override"
        exit 1
    fi
    log "DEBUG" "Xen dom0 image: $WIC_IMAGE"
}

hv_check_accel() {
    USE_KVM="false"
    if [ "$DISABLE_KVM" = "true" ]; then
        log "DEBUG" "KVM disabled by --no-kvm flag"
        return
    fi

    HOST_ARCH=$(uname -m)
    if [ "$HOST_ARCH" = "x86_64" ] && [ "$TARGET_ARCH" = "x86_64" ]; then
        if [ -w /dev/kvm ]; then
            USE_KVM="true"
            # Xen filters guest CPUID; -cpu host passes real features (AVX etc.)
            # through so an x86-64-v3 dom0 does not hit illegal-instruction traps.
            HV_MACHINE="-machine q35,i8042=off -cpu host"
            log "INFO" "KVM acceleration enabled"
        else
            log "WARN" "/dev/kvm not writable -- falling back to TCG (very slow)."
            log "WARN" "In WSL2, set nestedVirtualization=true in .wslconfig."
        fi
    fi
}

hv_find_command() {
    if ! command -v "$HV_CMD" >/dev/null 2>&1; then
        for path in \
            "${STAGING_BINDIR_NATIVE:-}" \
            "/usr/bin"; do
            if [ -n "$path" ] && [ -x "$path/$HV_CMD" ]; then
                HV_CMD="$path/$HV_CMD"
                break
            fi
        done
    fi

    if ! command -v "$HV_CMD" >/dev/null 2>&1 && [ ! -x "$HV_CMD" ]; then
        log "ERROR" "QEMU not found: $HV_CMD"
        exit 1
    fi
    log "DEBUG" "Using QEMU: $HV_CMD"
}

hv_get_console_device() {
    echo "$HV_CONSOLE"
}

# ============================================================================
# VM Configuration Building
# ============================================================================

hv_build_disk_opts() {
    # The dom0 wic is the only disk: Xen dom0 owns all guest storage, so no
    # rootfs / input / state disks are attached (unlike the plain qemu backend).
    HV_DISK_OPTS="-drive file=$WIC_IMAGE,format=raw,if=ide"
}

hv_build_network_opts() {
    # slirp user networking into dom0's uplink.  dom0 itself is a NAT router
    # for the DomU guests (XEN_DOM0_NETWORK=nat), so container port forwards
    # land on dom0's slirp NIC and dom0's DNAT/forwarding carries them to the
    # DomU.  Identical hostfwd handling to the plain qemu backend.
    HV_NET_OPTS=""
    # dom0's uplink is INFRASTRUCTURE, not per-container policy: image pull /
    # provisioning and the ssh transport need it, so it is always on and
    # decoupled from any container's network mode. A container's network
    # isolation is enforced at the container DomU's vif (see
    # vrunner-backend-xen.sh), NOT by starving dom0 -- so a `--no-network`
    # (AXIS block) run can pull its image yet still get no container network, and
    # can't poison a warm/memres dom0 that later runs need for provisioning.
    # VXN_DOM0_NETWORK=none deliberately airgaps dom0 (operator choice, not
    # per-run); the container's --no-network no longer reaches this decision.
    if [ "${VXN_DOM0_NETWORK:-on}" != "none" ]; then
        NETDEV_OPTS="user,id=net0"

        # SSH access to the running dom0 (localhost:${VXN_SSH_PORT}), for
        # debugging the mode-1 daemon and general dom0 introspection. Mirrors
        # boot-xen.sh's :18022->:22 forward.
        NETDEV_OPTS="$NETDEV_OPTS,hostfwd=tcp:127.0.0.1:${VXN_SSH_PORT:-18022}-:22"

        # Container-engine API forward: dom0's podman (or docker) serves its
        # Docker-compatible API on tcp:2375; forward it to the HOST's
        # 127.0.0.1:${VXN_API_PORT} so `vxn vexpose` + a docker/podman client
        # on the host drive dom0's engine (which uses vxn-oci-runtime -> DomU).
        # Bound to host loopback only (not 0.0.0.0) since the API is
        # unauthenticated. VXN_API_PORT=none disables it; a distinct port
        # deconflicts from a concurrent vdkr/vpdmn vexpose on 2375.
        if [ "${VXN_API_PORT:-2375}" != "none" ]; then
            NETDEV_OPTS="$NETDEV_OPTS,hostfwd=tcp:127.0.0.1:${VXN_API_PORT:-2375}-:2375"
        fi

        for pf in "${PORT_FORWARDS[@]}"; do
            HOST_PORT="${pf%%:*}"
            CONTAINER_PART="${pf#*:}"
            CONTAINER_PORT="${CONTAINER_PART%%/*}"
            if [[ "$CONTAINER_PART" == */* ]]; then
                PROTOCOL="${CONTAINER_PART##*/}"
            else
                PROTOCOL="tcp"
            fi
            # Bind to host loopback (not 0.0.0.0): QEMU slirp can't bind
            # 0.0.0.0 under WSL2, and localhost is what a WSL/host client uses.
            # For LAN exposure, front it with a portproxy (WSL) / firewall rule.
            NETDEV_OPTS="$NETDEV_OPTS,hostfwd=$PROTOCOL:127.0.0.1:$HOST_PORT-:$HOST_PORT"
            log "INFO" "Port forward: 127.0.0.1:$HOST_PORT -> dom0:$HOST_PORT (dom0 NATs to DomU:$CONTAINER_PORT)"
        done

        HV_NET_OPTS="-netdev $NETDEV_OPTS -device virtio-net-pci,netdev=net0"
    else
        HV_NET_OPTS="-nic none"
    fi
}

hv_build_9p_opts() {
    local share_dir="$1"
    local share_tag="$2"
    local extra_opts="${3:-}"
    HV_OPTS="$HV_OPTS -virtfs local,path=$share_dir,mount_tag=$share_tag,security_model=none${extra_opts:+,$extra_opts},id=$share_tag"
}

hv_build_daemon_opts() {
    HV_DAEMON_OPTS=""

    # virtio-serial command channel (name=vdkr).  dom0 binds
    # vxn-command-channel.sh to /dev/virtio-ports/vdkr; the host connects to
    # $DAEMON_SOCKET.  Same wiring as the qemu backend, so daemon_send() and
    # the ===PING===/===PONG=== readiness check work unchanged.
    HV_DAEMON_OPTS="$HV_DAEMON_OPTS -chardev socket,id=vdkr,path=$DAEMON_SOCKET,server=on,wait=off"
    HV_DAEMON_OPTS="$HV_DAEMON_OPTS -device virtio-serial-pci"
    HV_DAEMON_OPTS="$HV_DAEMON_OPTS -device virtserialport,chardev=vdkr,name=vdkr"

    # QMP socket for dynamic control (idle shutdown / quit).
    QMP_SOCKET="$DAEMON_SOCKET_DIR/qmp.sock"
    HV_DAEMON_OPTS="$HV_DAEMON_OPTS -qmp unix:$QMP_SOCKET,server,nowait"
}

hv_build_vm_cmd() {
    # NB: no -kernel / -initrd -- the .wic boots via firmware, and the Xen +
    # dom0 kernel cmdline is baked into the image's syslinux config.  So there
    # is also no -append (see hv_start_vm_*).
    HV_OPTS="$HV_MACHINE -nographic -smp $XEN_VCPUS -m $XEN_MEM -no-reboot"
    if [ "$USE_KVM" = "true" ]; then
        HV_OPTS="$HV_OPTS -enable-kvm"
    fi
    HV_OPTS="$HV_OPTS $HV_DISK_OPTS"
    HV_OPTS="$HV_OPTS $HV_NET_OPTS"
}

# ============================================================================
# VM Lifecycle
# ============================================================================

# The kernel_append argument is accepted for interface compatibility with
# vrunner.sh but deliberately ignored: this backend boots a firmware image,
# not a -kernel, so there is no cmdline to inject.  dom0's daemon responder is
# a systemd service, not a kernel-cmdline-selected daemon mode.

hv_start_vm_background() {
    local kernel_append="$1"   # ignored (wic boot, no -append)
    local log_file="$2"
    local timeout_val="$3"

    if [ "${VXN_DRY_RUN:-}" = "1" ]; then
        # L1 dry-run: record the exact command instead of launching QEMU.
        printf '%s %s\n' "$HV_CMD" "$HV_OPTS" > "$log_file"
        HV_VM_PID=""
        return 0
    fi

    # Detach stdio (see the qemu backend for the rationale: in daemon mode this
    # process outlives vrunner.sh and any inherited pipe would block a wrapping
    # test harness's read until QEMU exits).
    if [ -n "$timeout_val" ]; then
        timeout $timeout_val $HV_CMD $HV_OPTS </dev/null > "$log_file" 2>&1 &
    else
        $HV_CMD $HV_OPTS </dev/null > "$log_file" 2>&1 &
    fi
    HV_VM_PID=$!
}

hv_start_vm_foreground() {
    local kernel_append="$1"   # ignored (wic boot, no -append)
    $HV_CMD $HV_OPTS -serial mon:stdio
}

hv_is_vm_running() {
    [ -n "$HV_VM_PID" ] && [ -d "/proc/$HV_VM_PID" ]
}

hv_wait_vm_exit() {
    local timeout="${1:-30}"
    for i in $(seq 1 "$timeout"); do
        hv_is_vm_running || return 0
        sleep 1
    done
    return 1
}

hv_stop_vm() {
    if [ -n "$HV_VM_PID" ] && kill -0 "$HV_VM_PID" 2>/dev/null; then
        log "WARN" "QEMU still running, forcing termination..."
        kill $HV_VM_PID 2>/dev/null || true
        wait $HV_VM_PID 2>/dev/null || true
    fi
}

hv_destroy_vm() {
    if [ -n "$HV_VM_PID" ]; then
        kill -9 $HV_VM_PID 2>/dev/null || true
        wait $HV_VM_PID 2>/dev/null || true
    fi
}

hv_get_vm_id() {
    echo "$HV_VM_PID"
}

# ============================================================================
# Port Forwarding (handled by QEMU hostfwd, no separate setup needed)
# ============================================================================

hv_setup_port_forwards() {
    # QEMU port forwards are built into -netdev hostfwd=; dom0's NAT carries
    # them onward to the DomU.  Nothing extra at runtime.
    :
}

hv_cleanup_port_forwards() {
    # QEMU port forwards die with the process.
    :
}

# ============================================================================
# Idle Timeout / QMP Control
# ============================================================================

hv_idle_shutdown() {
    if [ -S "$QMP_SOCKET" ]; then
        echo '{"execute":"qmp_capabilities"}{"execute":"quit"}' | \
            socat - "UNIX-CONNECT:$QMP_SOCKET" >/dev/null 2>&1 || true
    fi
}

# Backend-specific daemon stop (vmemres stop). Without this, daemon_stop()
# sends ===SHUTDOWN=== -- which only stops the dom0 responder service, not the
# VM -- then polls 60s for a graceful guest exit that never happens. qemu-xen
# has no guest-side shutdown handshake and no attached state disk to flush
# (dom0 owns its own storage; the container-state.img is never attached here),
# so stop the VM directly via QMP quit, with a SIGKILL fallback.
hv_daemon_stop() {
    local qmp_sock="$DAEMON_SOCKET_DIR/qmp.sock"
    local pid=""
    [ -f "$DAEMON_PID_FILE" ] && pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null)

    if [ -S "$qmp_sock" ]; then
        log "INFO" "Stopping qemu-xen daemon via QMP quit..."
        echo '{"execute":"qmp_capabilities"}{"execute":"quit"}' | \
            socat - "UNIX-CONNECT:$qmp_sock" >/dev/null 2>&1 || true
    fi

    if [ -n "$pid" ]; then
        for _i in $(seq 1 20); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.5
        done
        if kill -0 "$pid" 2>/dev/null; then
            log "WARN" "QMP quit did not take; sending SIGKILL"
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi
    rm -f "$DAEMON_SOCKET_DIR/qmp.sock"
}
