#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vcontainer-init-common.sh
# Shared init functions for vdkr and vpdmn
#
# This file is sourced by vdkr-init.sh and vpdmn-init.sh after they set:
#   VCONTAINER_RUNTIME_NAME   - Tool name (vdkr or vpdmn)
#   VCONTAINER_RUNTIME_CMD    - Container command (docker or podman)
#   VCONTAINER_RUNTIME_PREFIX - Kernel param prefix (docker or podman)
#   VCONTAINER_STATE_DIR      - Storage directory (/var/lib/docker or /var/lib/containers/storage)
#   VCONTAINER_SHARE_NAME     - virtio-9p share name (vdkr_share or vpdmn_share)
#   VCONTAINER_VERSION        - Version string

# ============================================================================
# Environment Setup
# ============================================================================

setup_base_environment() {
    export LD_LIBRARY_PATH="/lib:/lib64:/usr/lib:/usr/lib64"
    export PATH="/bin:/sbin:/usr/bin:/usr/sbin"
    export HOME="/root"
    export USER="root"
    export LOGNAME="root"
}

# ============================================================================
# Hypervisor Detection
# ============================================================================

# Detect hypervisor type and set device prefixes accordingly.
# Must be called after /proc and /sys are mounted.
# Sets: HV_TYPE, BLK_PREFIX, NINE_P_TRANSPORT
detect_hypervisor() {
    # Check kernel cmdline for explicit block prefix (set by Xen backend)
    local cmdline_blk=""
    for param in $(cat /proc/cmdline 2>/dev/null); do
        case "$param" in
            vcontainer.blk=*) cmdline_blk="${param#vcontainer.blk=}" ;;
        esac
    done

    if [ -n "$cmdline_blk" ]; then
        # Explicit prefix from kernel cmdline (most reliable)
        BLK_PREFIX="$cmdline_blk"
        if [ "$cmdline_blk" = "xvd" ]; then
            HV_TYPE="xen"
            NINE_P_TRANSPORT="xen"
        else
            HV_TYPE="qemu"
            NINE_P_TRANSPORT="virtio"
        fi
    elif [ -d /proc/xen ] || grep -q "xen" /sys/hypervisor/type 2>/dev/null; then
        HV_TYPE="xen"
        BLK_PREFIX="xvd"
        NINE_P_TRANSPORT="xen"
    else
        HV_TYPE="qemu"
        BLK_PREFIX="vd"
        NINE_P_TRANSPORT="virtio"
    fi
}

# ============================================================================
# Filesystem Mounts
# ============================================================================

mount_base_filesystems() {
    # Mount essential filesystems if not already mounted
    mountpoint -q /dev  || mount -t devtmpfs devtmpfs /dev
    mountpoint -q /proc || mount -t proc proc /proc
    mountpoint -q /sys  || mount -t sysfs sysfs /sys

    # Mount devpts for pseudo-terminals (needed for interactive mode)
    mkdir -p /dev/pts
    mountpoint -q /dev/pts || mount -t devpts devpts /dev/pts

    # Detect hypervisor type now that /proc and /sys are available
    detect_hypervisor

    # Enable IP forwarding (container runtimes check this)
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # Configure loopback interface
    ip link set lo up
    ip addr add 127.0.0.1/8 dev lo 2>/dev/null || true
}

mount_tmpfs_dirs() {
    # These are tmpfs (rootfs is read-only)
    mount -t tmpfs tmpfs /tmp
    mount -t tmpfs tmpfs /run
    mount -t tmpfs tmpfs /mnt

    # Handle Yocto read-only-rootfs volatile directories
    # /var/log and /var/tmp are symlinks to volatile/log and volatile/tmp
    if [ -d /var/volatile ]; then
        mount -t tmpfs tmpfs /var/volatile
        mkdir -p /var/volatile/log /var/volatile/tmp
    fi

    # Fallback for non-volatile layouts
    mount -t tmpfs tmpfs /var/run 2>/dev/null || true
    mount -t tmpfs tmpfs /var/tmp 2>/dev/null || true

    # Create a writable /etc using tmpfs overlay
    mkdir -p /tmp/etc-overlay
    cp -a /etc/* /tmp/etc-overlay/ 2>/dev/null || true
    mount --bind /tmp/etc-overlay /etc
}

setup_cgroups() {
    mkdir -p /sys/fs/cgroup
    mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null || {
        mount -t tmpfs cgroup /sys/fs/cgroup 2>/dev/null || true
        for subsys in devices memory cpu,cpuacct blkio net_cls freezer pids; do
            subsys_dir=$(echo $subsys | cut -d, -f1)
            mkdir -p /sys/fs/cgroup/$subsys_dir
            mount -t cgroup -o $subsys cgroup /sys/fs/cgroup/$subsys_dir 2>/dev/null || true
        done
    }
}

# ============================================================================
# Quiet Boot / Logging
# ============================================================================

# Check for interactive mode (suppresses boot messages)
check_quiet_boot() {
    QUIET_BOOT=0
    for param in $(cat /proc/cmdline); do
        case "$param" in
            ${VCONTAINER_RUNTIME_PREFIX}_interactive=1) QUIET_BOOT=1 ;;
        esac
    done
}

# Logging function - suppresses output in interactive mode
log() {
    [ "$QUIET_BOOT" = "0" ] && echo "$@"
}

# ============================================================================
# Kernel Command Line Parsing
# ============================================================================

parse_cmdline() {
    # Initialize variables with defaults
    RUNTIME_CMD_B64=""
    RUNTIME_INPUT="none"
    RUNTIME_OUTPUT="text"
    RUNTIME_STATE="none"
    RUNTIME_NETWORK="0"
    RUNTIME_INTERACTIVE="0"
    RUNTIME_DAEMON="0"
    RUNTIME_9P="0"  # virtio-9p available for fast I/O
    RUNTIME_AUTH="0"  # registry auth config (config.json / auth.json) available on dedicated 9p share
    RUNTIME_IDLE_TIMEOUT="1800"  # Default: 30 minutes

    for param in $(cat /proc/cmdline); do
        case "$param" in
            ${VCONTAINER_RUNTIME_PREFIX}_cmd=*)
                RUNTIME_CMD_B64="${param#${VCONTAINER_RUNTIME_PREFIX}_cmd=}"
                ;;
            ${VCONTAINER_RUNTIME_PREFIX}_input=*)
                RUNTIME_INPUT="${param#${VCONTAINER_RUNTIME_PREFIX}_input=}"
                ;;
            ${VCONTAINER_RUNTIME_PREFIX}_output=*)
                RUNTIME_OUTPUT="${param#${VCONTAINER_RUNTIME_PREFIX}_output=}"
                ;;
            ${VCONTAINER_RUNTIME_PREFIX}_state=*)
                RUNTIME_STATE="${param#${VCONTAINER_RUNTIME_PREFIX}_state=}"
                ;;
            ${VCONTAINER_RUNTIME_PREFIX}_network=*)
                RUNTIME_NETWORK="${param#${VCONTAINER_RUNTIME_PREFIX}_network=}"
                ;;
            ${VCONTAINER_RUNTIME_PREFIX}_interactive=*)
                RUNTIME_INTERACTIVE="${param#${VCONTAINER_RUNTIME_PREFIX}_interactive=}"
                ;;
            ${VCONTAINER_RUNTIME_PREFIX}_daemon=*)
                RUNTIME_DAEMON="${param#${VCONTAINER_RUNTIME_PREFIX}_daemon=}"
                ;;
            ${VCONTAINER_RUNTIME_PREFIX}_idle_timeout=*)
                RUNTIME_IDLE_TIMEOUT="${param#${VCONTAINER_RUNTIME_PREFIX}_idle_timeout=}"
                ;;
            ${VCONTAINER_RUNTIME_PREFIX}_9p=*)
                RUNTIME_9P="${param#${VCONTAINER_RUNTIME_PREFIX}_9p=}"
                ;;
            ${VCONTAINER_RUNTIME_PREFIX}_auth=*)
                RUNTIME_AUTH="${param#${VCONTAINER_RUNTIME_PREFIX}_auth=}"
                ;;
        esac
    done

    # Decode the command (not required for daemon mode)
    RUNTIME_CMD=""
    if [ -n "$RUNTIME_CMD_B64" ]; then
        RUNTIME_CMD=$(echo "$RUNTIME_CMD_B64" | base64 -d 2>/dev/null)
    fi

    # Require command for non-daemon mode
    if [ -z "$RUNTIME_CMD" ] && [ "$RUNTIME_DAEMON" != "1" ]; then
        echo "===ERROR==="
        echo "No command provided (${VCONTAINER_RUNTIME_PREFIX}_cmd= missing)"
        sleep 2
        reboot -f
    fi

    log "Command: $RUNTIME_CMD"
    log "Input type: $RUNTIME_INPUT"
    log "Output type: $RUNTIME_OUTPUT"
    log "State type: $RUNTIME_STATE"
}

# ============================================================================
# Disk Detection
# ============================================================================

detect_disks() {
    log "Waiting for block devices..."
    sleep 2

    log "Block devices (${HV_TYPE:-qemu}, /dev/${BLK_PREFIX}*):"
    [ "$QUIET_BOOT" = "0" ] && ls -la /dev/${BLK_PREFIX}* 2>/dev/null || log "No /dev/${BLK_PREFIX}* devices"

    # Determine which disk is input and which is state
    # Drive layout (rootfs is always the first block device, mounted by preinit as /):
    #   QEMU: /dev/vda, /dev/vdb, /dev/vdc
    #   Xen:  /dev/xvda, /dev/xvdb, /dev/xvdc

    INPUT_DISK=""
    STATE_DISK=""

    if [ "$RUNTIME_INPUT" != "none" ] && [ "$RUNTIME_STATE" = "disk" ]; then
        INPUT_DISK="/dev/${BLK_PREFIX}b"
        STATE_DISK="/dev/${BLK_PREFIX}c"
    elif [ "$RUNTIME_STATE" = "disk" ]; then
        STATE_DISK="/dev/${BLK_PREFIX}b"
    elif [ "$RUNTIME_INPUT" != "none" ]; then
        INPUT_DISK="/dev/${BLK_PREFIX}b"
    fi
}

# ============================================================================
# Input Disk Handling
# ============================================================================

mount_input_disk() {
    mkdir -p /mnt/input

    if [ -n "$INPUT_DISK" ] && [ -b "$INPUT_DISK" ]; then
        log "Mounting input from $INPUT_DISK..."
        if mount -t ext4 "$INPUT_DISK" /mnt/input 2>&1; then
            log "SUCCESS: Mounted $INPUT_DISK"
            log "Input contents:"
            [ "$QUIET_BOOT" = "0" ] && ls -la /mnt/input/
        else
            log "WARNING: Failed to mount $INPUT_DISK, continuing without input"
            RUNTIME_INPUT="none"
        fi
    elif [ "$RUNTIME_INPUT" != "none" ]; then
        log "WARNING: No input device found, continuing without input"
        RUNTIME_INPUT="none"
    fi
}

# ============================================================================
# Registry auth share (docker config.json / podman auth.json)
# ============================================================================
# The host stages a validated credential file on a *dedicated* read-only 9p
# share tagged "${VCONTAINER_RUNTIME_NAME}_auth" (e.g. "vdkr_auth" or
# "vpdmn_auth"). That tag is separate from the general ${VCONTAINER_SHARE_NAME}
# used for input/output so credentials can't leak into storage.tar outputs or
# be overwritten by daemon_send_with_input.
#
# We mount read-only, nosuid, nodev, noexec at /mnt/auth. Callers are expected
# to copy the credential file into the runtime's canonical location with
# restrictive permissions and then call unmount_auth_share() so the guest
# filesystem no longer has an open reference to the host-side file.

AUTH_SHARE_TAG=""
AUTH_SHARE_MOUNT="/mnt/auth"

mount_auth_share() {
    if [ "$RUNTIME_AUTH" != "1" ]; then
        return 1
    fi

    AUTH_SHARE_TAG="${VCONTAINER_RUNTIME_NAME}_auth"
    mkdir -p "$AUTH_SHARE_MOUNT"

    # trans/version/cache match the existing 9p share mount. Add:
    #   ro      - guest can't mutate the host-side staging directory
    #   nosuid  - no setuid binaries can be executed from the share
    #   nodev   - no device nodes honoured even if crafted
    #   noexec  - no code can execute from the share (auth.json is pure data)
    if mount -t 9p \
        -o trans=${NINE_P_TRANSPORT},version=9p2000.L,cache=none,ro,nosuid,nodev,noexec \
        "$AUTH_SHARE_TAG" "$AUTH_SHARE_MOUNT" 2>/dev/null; then
        log "Mounted auth 9p share at $AUTH_SHARE_MOUNT (tag: $AUTH_SHARE_TAG, ro)"
        return 0
    fi

    log "WARNING: Could not mount auth 9p share ($AUTH_SHARE_TAG)"
    RUNTIME_AUTH="0"
    return 1
}

unmount_auth_share() {
    if mountpoint -q "$AUTH_SHARE_MOUNT" 2>/dev/null; then
        umount "$AUTH_SHARE_MOUNT" 2>/dev/null || \
            umount -l "$AUTH_SHARE_MOUNT" 2>/dev/null || true
    fi
    rmdir "$AUTH_SHARE_MOUNT" 2>/dev/null || true
}

# ============================================================================
# Network Configuration
# ============================================================================

configure_networking() {
    if [ "$RUNTIME_NETWORK" = "1" ]; then
        log "Configuring network..."

        # Find the network interface (usually eth0 or enp0s* with virtio)
        NET_IFACE=""
        for iface in eth0 enp0s2 enp0s3 ens3; do
            if [ -d "/sys/class/net/$iface" ]; then
                NET_IFACE="$iface"
                break
            fi
        done

        if [ -n "$NET_IFACE" ]; then
            log "Found network interface: $NET_IFACE"

            # Bring up the interface
            ip link set "$NET_IFACE" up

            if [ "$HV_TYPE" = "xen" ]; then
                # Xen bridge networking: use DHCP or static config
                # Try DHCP first if udhcpc is available
                if command -v udhcpc >/dev/null 2>&1; then
                    log "Requesting IP via DHCP (Xen bridge)..."
                    udhcpc -i "$NET_IFACE" -t 5 -T 3 -q 2>/dev/null || {
                        log "DHCP failed, using static fallback"
                        ip addr add 10.0.0.15/24 dev "$NET_IFACE"
                        ip route add default via 10.0.0.1
                    }
                else
                    # Static fallback for Xen bridge
                    ip addr add 10.0.0.15/24 dev "$NET_IFACE"
                    ip route add default via 10.0.0.1
                fi
            else
                # QEMU slirp provides:
                #   Guest IP: 10.0.2.15/24
                #   Gateway:  10.0.2.2
                #   DNS:      10.0.2.3
                ip addr add 10.0.2.15/24 dev "$NET_IFACE"
                ip route add default via 10.0.2.2
            fi

            # Configure DNS
            mkdir -p /etc
            rm -f /etc/resolv.conf
            if [ "$HV_TYPE" = "xen" ]; then
                cat > /etc/resolv.conf << 'DNSEOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
DNSEOF
            else
                cat > /etc/resolv.conf << 'DNSEOF'
nameserver 10.0.2.3
nameserver 8.8.8.8
nameserver 1.1.1.1
DNSEOF
            fi

            sleep 1

            # Verify connectivity
            local gw_ip
            gw_ip=$(ip route | awk '/default/{print $3}' | head -n 1)
            log "Testing network connectivity..."
            if [ -n "$gw_ip" ] && ping -c 1 -W 3 "$gw_ip" >/dev/null 2>&1; then
                log "  Gateway ($gw_ip): OK"
            else
                log "  Gateway: FAILED"
            fi

            if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
                log "  External (8.8.8.8): OK"
            else
                log "  External (8.8.8.8): FAILED (may be filtered)"
            fi

            local my_ip
            my_ip=$(ip -4 addr show "$NET_IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -n 1)
            log "Network configured: $NET_IFACE ($my_ip)"
            [ "$QUIET_BOOT" = "0" ] && ip addr show "$NET_IFACE"
            [ "$QUIET_BOOT" = "0" ] && ip route
            [ "$QUIET_BOOT" = "0" ] && cat /etc/resolv.conf
        else
            log "WARNING: No network interface found"
            [ "$QUIET_BOOT" = "0" ] && ls /sys/class/net/
        fi
    else
        log "Networking: disabled"
    fi
}

# ============================================================================
# Daemon Mode
# ============================================================================

run_daemon_mode() {
    log "=== Daemon Mode ==="
    log "Idle timeout: ${RUNTIME_IDLE_TIMEOUT}s"

    # Find the virtio-serial port for command channel
    DAEMON_PORT=""
    for port in /dev/vport0p1 /dev/vport1p1 /dev/vport2p1 /dev/virtio-ports/${VCONTAINER_RUNTIME_NAME} /dev/hvc1; do
        if [ -c "$port" ]; then
            DAEMON_PORT="$port"
            log "Found virtio-serial port: $port"
            break
        fi
    done

    if [ -z "$DAEMON_PORT" ]; then
        log "ERROR: Could not find virtio-serial port for daemon mode"
        log "Available devices:"
        ls -la /dev/hvc* /dev/vport* /dev/virtio-ports/ 2>/dev/null || true
        sleep 5
        reboot -f
    fi

    log "Using virtio-serial port: $DAEMON_PORT"

    # Mount virtio-9p shared directory for file I/O
    mkdir -p /mnt/share
    MOUNT_ERR=$(mount -t 9p -o trans=${NINE_P_TRANSPORT},version=9p2000.L,cache=none ${VCONTAINER_SHARE_NAME} /mnt/share 2>&1)
    if [ $? -eq 0 ]; then
        log "Mounted 9p share at /mnt/share (transport: ${NINE_P_TRANSPORT})"
    else
        log "WARNING: Could not mount 9p share: $MOUNT_ERR"
        log "Available filesystems:"
        cat /proc/filesystems 2>/dev/null | head -20
    fi

    # Open bidirectional FD to the virtio-serial port
    exec 3<>"$DAEMON_PORT"

    log "Daemon ready, waiting for commands..."

    # Start idle timeout watchdog
    # Note: 'read -t' doesn't work reliably on non-terminal fds (like virtio-serial),
    # so we use a background watchdog that tracks activity via a timestamp file.
    ACTIVITY_FILE="/tmp/.daemon_activity"
    touch "$ACTIVITY_FILE"
    DAEMON_PID=$$

    # Watchdog process - writes container status to shared directory for host-side
    # Host-side handles shutdown via QMP; guest-side shutdown is disabled but preserved
    CONTAINER_STATUS_FILE="/mnt/share/.containers_running"

    # Scale check interval to idle timeout (check ~5 times before timeout)
    CHECK_INTERVAL=$((RUNTIME_IDLE_TIMEOUT / 5))
    [ "$CHECK_INTERVAL" -lt 10 ] && CHECK_INTERVAL=10
    [ "$CHECK_INTERVAL" -gt 60 ] && CHECK_INTERVAL=60

    (
        # Close inherited virtio-serial fd to prevent output leaking to host
        exec 3>&-

        while true; do
            sleep "$CHECK_INTERVAL"
            if [ ! -f "$ACTIVITY_FILE" ]; then
                # Activity file removed = clean shutdown in progress
                rm -f "$CONTAINER_STATUS_FILE" 2>/dev/null
                exit 0
            fi

            # Check for running containers and write status to shared file
            # Host-side reads this file instead of sending socket commands
            RUNNING=$("$VCONTAINER_RUNTIME_CMD" ps -q 2>/dev/null)
            if [ -n "$RUNNING" ]; then
                echo "$RUNNING" > "$CONTAINER_STATUS_FILE" 2>/dev/null || true
            else
                rm -f "$CONTAINER_STATUS_FILE" 2>/dev/null || true
            fi

            # Guest-side shutdown logic - DISABLED, host-side QMP is more reliable
            # Kept for potential future use if host-side becomes unavailable
            : << 'DISABLED_GUEST_SHUTDOWN'
            LAST_ACTIVITY=$(stat -c %Y "$ACTIVITY_FILE" 2>/dev/null || echo 0)
            NOW=$(date +%s)
            IDLE_SECONDS=$((NOW - LAST_ACTIVITY))
            if [ "$IDLE_SECONDS" -ge "$RUNTIME_IDLE_TIMEOUT" ]; then
                if [ -n "$RUNNING" ]; then
                    # Containers are running - reset activity and skip shutdown
                    echo "[watchdog] Containers still running, resetting idle timer" >> /dev/kmsg 2>/dev/null || true
                    touch "$ACTIVITY_FILE"
                    continue
                fi
                echo "[watchdog] Idle timeout (${IDLE_SECONDS}s >= ${RUNTIME_IDLE_TIMEOUT}s), no containers running, shutting down..." >> /dev/kmsg 2>/dev/null || true
                rm -f "$CONTAINER_STATUS_FILE" 2>/dev/null
                kill -TERM "$DAEMON_PID" 2>/dev/null
                exit 0
            fi
DISABLED_GUEST_SHUTDOWN
        done
    ) &
    WATCHDOG_PID=$!
    log "Started idle watchdog (PID: $WATCHDOG_PID, timeout: ${RUNTIME_IDLE_TIMEOUT}s)"

    # Trap to clean up watchdog on exit and power off VM
    # Use reboot -f which works with QEMU's -no-reboot flag to exit cleanly
    trap 'log "Idle timeout triggered by watchdog"; log "Calling reboot -f"; sync; /usr/sbin/reboot -f' TERM
    trap 'rm -f "$ACTIVITY_FILE"; kill $WATCHDOG_PID 2>/dev/null; exit' INT

    # Command loop
    while true; do
        CMD_B64=""
        read -r CMD_B64 <&3
        READ_EXIT=$?

        if [ $READ_EXIT -eq 0 ] && [ -n "$CMD_B64" ]; then
            # Update activity timestamp
            touch "$ACTIVITY_FILE"
            log "Received: '$CMD_B64'"
            # Handle special commands
            case "$CMD_B64" in
                "===PING===")
                    echo "===PONG===" | cat >&3
                    continue
                    ;;
                "===SHUTDOWN===")
                    log "Received shutdown command"
                    echo "===SHUTTING_DOWN===" | cat >&3
                    break
                    ;;
            esac

            # Decode command
            CMD=$(echo "$CMD_B64" | base64 -d 2>/dev/null)
            if [ -z "$CMD" ]; then
                printf "===ERROR===\nFailed to decode command\n===END===\n" | cat >&3
                continue
            fi

            # Check for interactive command
            if echo "$CMD" | grep -q "^===INTERACTIVE==="; then
                CMD="${CMD#===INTERACTIVE===}"
                log "Interactive command: $CMD"

                printf "===INTERACTIVE_READY===\n" >&3

                export TERM=linux
                script -qf -c "$CMD" /dev/null <&3 >&3 2>&1
                INTERACTIVE_EXIT=$?

                sleep 0.5
                printf "\n===INTERACTIVE_END=%d===\n" "$INTERACTIVE_EXIT" >&3

                log "Interactive command completed (exit: $INTERACTIVE_EXIT)"
                continue
            fi

            # Check if command needs input from shared directory
            NEEDS_INPUT=false
            if echo "$CMD" | grep -q "^===USE_INPUT==="; then
                NEEDS_INPUT=true
                CMD="${CMD#===USE_INPUT===}"
                log "Command needs input from shared directory"
            fi

            # Check if this is a pull command that needs fallback handling
            # (try registry first, fall back to Docker Hub)
            USE_PULL_FALLBACK=false
            if type is_pull_command >/dev/null 2>&1 && type execute_pull_with_fallback >/dev/null 2>&1; then
                if is_pull_command "$CMD"; then
                    USE_PULL_FALLBACK=true
                    log "Using pull with registry fallback"
                fi
            fi

            # Transform command if runtime provides a transform function
            # (e.g., vdkr transforms unqualified images to use default registry)
            # Note: Pull commands are NOT transformed - they use fallback logic
            if [ "$USE_PULL_FALLBACK" != "true" ]; then
                if type transform_docker_command >/dev/null 2>&1 && [ -n "$DOCKER_DEFAULT_REGISTRY" ]; then
                    CMD=$(transform_docker_command "$CMD")
                fi
            fi

            log "Executing: $CMD"

            # Verify shared directory has content if needed
            if [ "$NEEDS_INPUT" = "true" ]; then
                if ! mountpoint -q /mnt/share; then
                    printf "===ERROR===\nvirtio-9p share not mounted\n===END===\n" | cat >&3
                    continue
                fi
                if [ -z "$(ls -A /mnt/share 2>/dev/null)" ]; then
                    printf "===ERROR===\nShared directory is empty\n===END===\n" | cat >&3
                    continue
                fi
                log "Shared directory contents:"
                ls -la /mnt/share/ 2>/dev/null || true
            fi

            # Replace {INPUT} placeholder
            INPUT_PATH="/mnt/share"
            CMD=$(echo "$CMD" | sed "s|{INPUT}|$INPUT_PATH|g")

            # Execute command
            EXEC_OUTPUT="/tmp/daemon_output.txt"
            EXEC_EXIT_CODE=0
            if [ "$USE_PULL_FALLBACK" = "true" ]; then
                # Pull commands use registry-first, Docker Hub fallback
                execute_pull_with_fallback "$CMD" > "$EXEC_OUTPUT" 2>&1 || EXEC_EXIT_CODE=$?
            else
                eval "$CMD" > "$EXEC_OUTPUT" 2>&1 || EXEC_EXIT_CODE=$?
            fi

            # Clean up shared directory
            if [ "$NEEDS_INPUT" = "true" ]; then
                log "Cleaning shared directory..."
                rm -rf /mnt/share/* 2>/dev/null || true
            fi

            # Send response
            {
                echo "===OUTPUT_START==="
                cat "$EXEC_OUTPUT"
                echo "===OUTPUT_END==="
                echo "===EXIT_CODE=$EXEC_EXIT_CODE==="
                echo "===END==="
            } | cat >&3

            log "Command completed (exit code: $EXEC_EXIT_CODE)"
        else
            # Read returned non-zero or empty - host closed connection or EOF
            # Idle timeout is handled by the watchdog process
            sleep 0.1
        fi
    done

    # Clean shutdown
    rm -f "$ACTIVITY_FILE"
    kill $WATCHDOG_PID 2>/dev/null
    exec 3>&-
    log "Daemon shutting down..."
}

# ============================================================================
# Command Execution (non-daemon mode)
# ============================================================================

prepare_input_path() {
    INPUT_PATH=""
    if [ "$RUNTIME_INPUT" = "oci" ] && [ -d "/mnt/input" ]; then
        INPUT_PATH="/mnt/input"
    elif [ "$RUNTIME_INPUT" = "tar" ] && [ -d "/mnt/input" ]; then
        INPUT_PATH=$(find /mnt/input -name "*.tar" -o -name "*.tar.gz" | head -n 1)
        [ -z "$INPUT_PATH" ] && INPUT_PATH="/mnt/input"
    elif [ "$RUNTIME_INPUT" = "dir" ]; then
        INPUT_PATH="/mnt/input"
    fi
    export INPUT_PATH
}

execute_command() {
    # Substitute {INPUT} placeholder
    RUNTIME_CMD_FINAL=$(echo "$RUNTIME_CMD" | sed "s|{INPUT}|$INPUT_PATH|g")

    log "=== Executing ${VCONTAINER_RUNTIME_CMD} Command ==="
    log "Command: $RUNTIME_CMD_FINAL"
    log ""

    if [ "$RUNTIME_INTERACTIVE" = "1" ]; then
        # Interactive mode
        export TERM=linux
        printf '\r\033[K'
        eval "$RUNTIME_CMD_FINAL"
        EXEC_EXIT_CODE=$?
    else
        # Non-interactive mode
        EXEC_OUTPUT="/tmp/runtime_output.txt"
        EXEC_EXIT_CODE=0
        eval "$RUNTIME_CMD_FINAL" > "$EXEC_OUTPUT" 2>&1 || EXEC_EXIT_CODE=$?

        log "Exit code: $EXEC_EXIT_CODE"

        case "$RUNTIME_OUTPUT" in
        text)
            echo "===OUTPUT_START==="
            cat "$EXEC_OUTPUT"
            echo "===OUTPUT_END==="
            echo "===EXIT_CODE=$EXEC_EXIT_CODE==="
            ;;

        tar)
            if [ -f /tmp/output.tar ]; then
                dmesg -n 1
                echo "===TAR_START==="
                base64 /tmp/output.tar
                echo "===TAR_END==="
                echo "===EXIT_CODE=$EXEC_EXIT_CODE==="
            else
                echo "===ERROR==="
                echo "Expected /tmp/output.tar but file not found"
                echo "Command output:"
                cat "$EXEC_OUTPUT"
            fi
            ;;

        storage)
            # This is handled by runtime-specific code
            handle_storage_output
            ;;

        *)
            echo "===ERROR==="
            echo "Unknown output type: $RUNTIME_OUTPUT"
            ;;
        esac
    fi
}

# ============================================================================
# Graceful Shutdown
# ============================================================================

graceful_shutdown() {
    log "=== Shutting down gracefully ==="

    # Runtime-specific cleanup (implemented by sourcing script)
    if type stop_runtime_daemons >/dev/null 2>&1; then
        stop_runtime_daemons
    fi

    sync

    # Unmount state disk if mounted
    if mount | grep -q "$VCONTAINER_STATE_DIR"; then
        log "Unmounting state disk..."
        sync
        umount "$VCONTAINER_STATE_DIR" || {
            log "Warning: umount failed, trying lazy unmount"
            umount -l "$VCONTAINER_STATE_DIR" 2>/dev/null || true
        }
    fi

    # Unmount input
    umount /mnt/input 2>/dev/null || true

    # Final sync and flush
    sync
    for dev in /dev/${BLK_PREFIX}*; do
        [ -b "$dev" ] && blockdev --flushbufs "$dev" 2>/dev/null || true
    done
    sync
    sleep 2

    log "=== ${VCONTAINER_RUNTIME_NAME} Complete ==="
    # Use reboot -f which works with QEMU's -no-reboot flag to exit cleanly
    reboot -f
}
