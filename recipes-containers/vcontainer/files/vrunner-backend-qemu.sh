#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vrunner-backend-qemu.sh
# QEMU hypervisor backend for vrunner.sh
#
# This backend implements the hypervisor interface for QEMU.
# It is sourced by vrunner.sh when VCONTAINER_HYPERVISOR=qemu.
#
# Backend interface functions:
#   hv_setup_arch()            - Set arch-specific QEMU command and machine type
#   hv_check_accel()           - Detect KVM acceleration
#   hv_build_disk_opts()       - Build QEMU disk drive options
#   hv_build_network_opts()    - Build QEMU network options
#   hv_build_9p_opts()         - Build QEMU virtio-9p options
#   hv_build_daemon_opts()     - Build QEMU daemon mode options (serial, QMP)
#   hv_build_vm_cmd()          - Assemble final QEMU command line
#   hv_start_vm_background()   - Start QEMU in background, capture PID
#   hv_start_vm_foreground()   - Start QEMU in foreground (interactive)
#   hv_is_vm_running()         - Check if QEMU process is alive
#   hv_wait_vm_exit()          - Wait for QEMU to exit
#   hv_stop_vm()               - Graceful shutdown via QMP
#   hv_destroy_vm()            - Force kill QEMU process
#   hv_get_vm_id()             - Return QEMU PID
#   hv_setup_port_forwards()   - Port forwards via QEMU hostfwd (built into netdev)
#   hv_cleanup_port_forwards() - No-op for QEMU (forwards die with process)
#   hv_idle_shutdown()         - Send QMP quit for idle timeout
#   hv_get_console_device()    - Return arch-specific console device name

# ============================================================================
# Architecture Setup
# ============================================================================

hv_setup_arch() {
    case "$TARGET_ARCH" in
        aarch64)
            KERNEL_IMAGE="$BLOB_DIR/aarch64/Image"
            INITRAMFS="$BLOB_DIR/aarch64/initramfs.cpio.gz"
            ROOTFS_IMG="$BLOB_DIR/aarch64/rootfs.img"
            HV_CMD="qemu-system-aarch64"
            HV_MACHINE="-M virt -cpu cortex-a57"
            HV_CONSOLE="ttyAMA0"
            ;;
        x86_64)
            KERNEL_IMAGE="$BLOB_DIR/x86_64/bzImage"
            INITRAMFS="$BLOB_DIR/x86_64/initramfs.cpio.gz"
            ROOTFS_IMG="$BLOB_DIR/x86_64/rootfs.img"
            HV_CMD="qemu-system-x86_64"
            HV_MACHINE="-M q35 -cpu Skylake-Client"
            HV_CONSOLE="ttyS0"
            ;;
        *)
            log "ERROR" "Unsupported architecture: $TARGET_ARCH"
            exit 1
            ;;
    esac
}

hv_check_accel() {
    USE_KVM="false"
    if [ "$DISABLE_KVM" = "true" ]; then
        log "DEBUG" "KVM disabled by --no-kvm flag"
        return
    fi

    HOST_ARCH=$(uname -m)
    if [ "$HOST_ARCH" = "$TARGET_ARCH" ] || \
       { [ "$HOST_ARCH" = "x86_64" ] && [ "$TARGET_ARCH" = "x86_64" ]; }; then
        if [ -w /dev/kvm ]; then
            USE_KVM="true"
            case "$TARGET_ARCH" in
                x86_64)  HV_MACHINE="-M q35 -cpu host" ;;
                aarch64) HV_MACHINE="-M virt -cpu host" ;;
            esac
            log "INFO" "KVM acceleration enabled"
        else
            log "DEBUG" "KVM not available (no write access to /dev/kvm)"
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
    # Rootfs (read-only)
    HV_DISK_OPTS="-drive file=$ROOTFS_IMG,if=virtio,format=raw,readonly=on"

    # Input disk (if any)
    if [ -n "$DISK_OPTS" ]; then
        HV_DISK_OPTS="$HV_DISK_OPTS $DISK_OPTS"
    fi

    # State disk (if any)
    if [ -n "$STATE_DISK_OPTS" ]; then
        HV_DISK_OPTS="$HV_DISK_OPTS $STATE_DISK_OPTS"
    fi
}

hv_build_network_opts() {
    HV_NET_OPTS=""
    if [ "$NETWORK" = "true" ]; then
        NETDEV_OPTS="user,id=net0"

        # Add port forwards
        for pf in "${PORT_FORWARDS[@]}"; do
            HOST_PORT="${pf%%:*}"
            CONTAINER_PART="${pf#*:}"
            CONTAINER_PORT="${CONTAINER_PART%%/*}"
            if [[ "$CONTAINER_PART" == */* ]]; then
                PROTOCOL="${CONTAINER_PART##*/}"
            else
                PROTOCOL="tcp"
            fi
            NETDEV_OPTS="$NETDEV_OPTS,hostfwd=$PROTOCOL::$HOST_PORT-:$HOST_PORT"
            log "INFO" "Port forward: host:$HOST_PORT -> VM:$HOST_PORT (Docker maps to container:$CONTAINER_PORT)"
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

    # virtio-serial for command channel
    HV_DAEMON_OPTS="$HV_DAEMON_OPTS -chardev socket,id=vdkr,path=$DAEMON_SOCKET,server=on,wait=off"
    HV_DAEMON_OPTS="$HV_DAEMON_OPTS -device virtio-serial-pci"
    HV_DAEMON_OPTS="$HV_DAEMON_OPTS -device virtserialport,chardev=vdkr,name=vdkr"

    # QMP socket for dynamic control
    QMP_SOCKET="$DAEMON_SOCKET_DIR/qmp.sock"
    HV_DAEMON_OPTS="$HV_DAEMON_OPTS -qmp unix:$QMP_SOCKET,server,nowait"
}

hv_build_vm_cmd() {
    HV_OPTS="$HV_MACHINE -nographic -smp 2 -m 2048 -no-reboot"
    if [ "$USE_KVM" = "true" ]; then
        HV_OPTS="$HV_OPTS -enable-kvm"
    fi
    HV_OPTS="$HV_OPTS -kernel $KERNEL_IMAGE"
    HV_OPTS="$HV_OPTS -initrd $INITRAMFS"
    HV_OPTS="$HV_OPTS $HV_DISK_OPTS"
    HV_OPTS="$HV_OPTS $HV_NET_OPTS"
}

# ============================================================================
# VM Lifecycle
# ============================================================================

hv_start_vm_background() {
    local kernel_append="$1"
    local log_file="$2"
    local timeout_val="$3"

    # Fully detach stdio from the invoking shell. In daemon mode this
    # process outlives vrunner.sh, and if the CLI that invoked us was
    # wrapped by something that pipes stdout/stderr (e.g. a test harness
    # using subprocess.run(capture_output=True)), any inherited fd here
    # would block the parent's read/communicate() call until QEMU exits.
    # Redirect fd 0 from /dev/null and fd 1/fd 2 to the log file.
    if [ -n "$timeout_val" ]; then
        timeout $timeout_val $HV_CMD $HV_OPTS -append "$kernel_append" </dev/null > "$log_file" 2>&1 &
    else
        $HV_CMD $HV_OPTS -append "$kernel_append" </dev/null > "$log_file" 2>&1 &
    fi
    HV_VM_PID=$!
}

hv_start_vm_foreground() {
    local kernel_append="$1"
    $HV_CMD $HV_OPTS -append "$kernel_append"
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
    # QEMU port forwards are built into the -netdev hostfwd= options
    # Nothing extra to do at runtime
    :
}

hv_cleanup_port_forwards() {
    # QEMU port forwards die with the process
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
