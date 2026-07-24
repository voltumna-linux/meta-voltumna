#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vpdmn-init.sh
# Init script for vpdmn: execute arbitrary podman commands in QEMU
#
# This script runs on a real ext4 filesystem after switch_root from initramfs.
# The preinit script mounted /dev/vda (rootfs.img) and did switch_root to us.
#
# Drive layout (rootfs.img is always /dev/vda, mounted as /):
#   /dev/vda = rootfs.img (this script runs from here, mounted as /)
#   /dev/vdb = input disk (optional, OCI/tar/dir data)
#   /dev/vdc = state disk (optional, persistent Podman storage)
#
# Kernel parameters:
#   podman_cmd=<base64>    Base64-encoded podman command + args
#   podman_input=<type>    Input type: none, oci, tar, dir (default: none)
#   podman_output=<type>   Output type: text, tar, storage (default: text)
#   podman_state=<type>    State type: none, disk (default: none)
#   podman_network=1       Enable networking (configure eth0, DNS)
#   podman_auth=1          A pre-built registry auth file (docker config.json
#                          schema, "auths" block) is available on a dedicated
#                          read-only 9p share tagged "vpdmn_auth" (mounted at
#                          /mnt/auth). Installed as /run/containers/0/auth.json
#                          (the rootful podman default), and exported via
#                          $REGISTRY_AUTH_FILE.
#
# Version: 1.1.0
#
# Note: Podman is daemonless - no containerd/dockerd required!

# Set runtime-specific parameters before sourcing common code
VCONTAINER_RUNTIME_NAME="vpdmn"
VCONTAINER_RUNTIME_CMD="podman"
VCONTAINER_RUNTIME_PREFIX="podman"
VCONTAINER_STATE_DIR="/var/lib/containers/storage"
VCONTAINER_SHARE_NAME="vpdmn_share"
VCONTAINER_VERSION="1.1.0"

# Source common init functions
# When installed as /init, common file is at /vcontainer-init-common.sh
. /vcontainer-init-common.sh

# ============================================================================
# Podman-Specific Functions
# ============================================================================

setup_podman_environment() {
    # Podman needs XDG_RUNTIME_DIR
    export XDG_RUNTIME_DIR="/run/user/0"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
}

setup_podman_mounts() {
    # Podman needs /dev/shm
    mkdir -p /dev/shm
    mount -t tmpfs tmpfs /dev/shm

    # Mount /var/volatile for Yocto's volatile symlinks (/var/tmp -> volatile/tmp, etc.)
    mkdir -p /var/volatile
    mount -t tmpfs tmpfs /var/volatile
    mkdir -p /var/volatile/tmp /var/volatile/log /var/volatile/run /var/volatile/cache

    # Also mount /var/cache directly (not a symlink)
    mount -t tmpfs tmpfs /var/cache
}

setup_podman_storage() {
    mkdir -p /run/lock

    # /var/lib/containers exists in rootfs.img (read-only), mount tmpfs over it
    mount -t tmpfs tmpfs /var/lib/containers
    mkdir -p /var/lib/containers/storage

    # Handle Podman storage
    if [ -n "$STATE_DISK" ] && [ -b "$STATE_DISK" ]; then
        log "Mounting state disk $STATE_DISK as /var/lib/containers/storage..."
        if mount -t ext4 "$STATE_DISK" /var/lib/containers/storage 2>&1; then
            log "SUCCESS: Mounted $STATE_DISK as Podman storage"
            log "Podman storage contents:"
            [ "$QUIET_BOOT" = "0" ] && ls -la /var/lib/containers/storage/ 2>/dev/null || log "(empty)"
        else
            log "WARNING: Failed to mount state disk, using tmpfs fallback"
            RUNTIME_STATE="none"
        fi
    else
        log "Using tmpfs for Podman storage (ephemeral)..."
    fi
}

verify_podman() {
    # Podman is daemonless - just verify it's available
    if [ -x "/usr/bin/podman" ]; then
        log "Podman available: $(podman --version 2>/dev/null || echo 'version unknown')"
    else
        echo "===ERROR==="
        echo "Podman not found at /usr/bin/podman"
        sleep 2
        reboot -f
    fi
}

# Install a user-supplied registry auth file from the dedicated read-only
# auth 9p share (mounted at /mnt/auth by mount_auth_share). Podman accepts
# the same "auths" JSON schema as docker config.json, so we can copy directly.
#
# Canonical rootful path is /run/containers/0/auth.json; we also export
# $REGISTRY_AUTH_FILE so it works regardless of podman's search order.
#
# Security posture matches vdkr-init.sh install_auth_config:
#   * Source is a separate read-only 9p tag ("vpdmn_auth") so it cannot leak
#     into /mnt/share outputs.
#   * Target has mode 0600; containing dir has mode 0700.
#   * /mnt/auth is unmounted immediately after copy so user workloads in the
#     VM have no open reference to the host-side staging directory.
install_auth_config() {
    if [ "$RUNTIME_AUTH" != "1" ]; then
        return 0
    fi

    if ! mount_auth_share; then
        log "WARNING: podman_auth=1 was set but the auth 9p share did not mount"
        return 1
    fi

    local src="$AUTH_SHARE_MOUNT/config.json"
    if [ ! -f "$src" ]; then
        log "WARNING: expected $src on auth share but file is missing"
        unmount_auth_share
        return 1
    fi

    # Rootful podman's default auth path
    local auth_dir="/run/containers/0"
    local auth_file="$auth_dir/auth.json"

    mkdir -p "$auth_dir"
    chmod 700 "$auth_dir"

    if cp "$src" "$auth_file" 2>/dev/null; then
        chmod 600 "$auth_file"
        export REGISTRY_AUTH_FILE="$auth_file"
        log "Installed registry auth config at $auth_file"
    else
        log "ERROR: failed to copy auth config to $auth_file"
        unmount_auth_share
        return 1
    fi

    unmount_auth_share
    return 0
}

# Podman is daemonless - nothing to stop
stop_runtime_daemons() {
    :
}

handle_storage_output() {
    # Export entire podman storage
    # Tar from inside /var/lib/containers/storage so paths are vfs-images/... directly
    echo "Packaging Podman storage..."
    if ! cd /var/lib/containers/storage; then
        echo "===ERROR==="
        echo "Failed to cd to /var/lib/containers/storage"
        echo "Contents of /var/lib/containers:"
        ls -la /var/lib/containers/ 2>&1 || echo "(not found)"
        poweroff -f
        exit 1
    fi
    tar -cf /tmp/storage.tar .

    STORAGE_SIZE=$(stat -c%s /tmp/storage.tar 2>/dev/null || echo "0")
    echo "Storage size: $STORAGE_SIZE bytes"

    if [ "$STORAGE_SIZE" -gt 1000 ]; then
        # Use virtio-9p if available (much faster than console base64)
        if [ "$RUNTIME_9P" = "1" ] && mountpoint -q /mnt/share 2>/dev/null; then
            echo "Using virtio-9p for storage output (fast path)"
            cp /tmp/storage.tar /mnt/share/storage.tar
            sync
            echo "===9P_STORAGE_DONE==="
            echo "===EXIT_CODE=$EXEC_EXIT_CODE==="
        else
            # Fallback: base64 to console (slow)
            dmesg -n 1
            echo "===STORAGE_START==="
            base64 /tmp/storage.tar
            echo "===STORAGE_END==="
            echo "===EXIT_CODE=$EXEC_EXIT_CODE==="
        fi
    else
        echo "===ERROR==="
        echo "Storage too small"
    fi
}

# ============================================================================
# Main
# ============================================================================

# Initialize base environment
setup_base_environment
setup_podman_environment
mount_base_filesystems

# Check for quiet boot mode
check_quiet_boot

log "=== vpdmn Init ==="
log "Version: $VCONTAINER_VERSION"

# Mount tmpfs directories and Podman-specific mounts
mount_tmpfs_dirs
setup_podman_mounts
setup_cgroups

# Parse kernel command line
parse_cmdline

# Mount 9p share if available (for fast storage output in batch-import mode)
if [ "$RUNTIME_9P" = "1" ]; then
    mkdir -p /mnt/share
    if mount -t 9p -o trans=${NINE_P_TRANSPORT},version=9p2000.L,cache=none ${VCONTAINER_SHARE_NAME} /mnt/share 2>/dev/null; then
        log "Mounted 9p share at /mnt/share (transport: ${NINE_P_TRANSPORT})"
    else
        log "WARNING: Could not mount 9p share, falling back to console output"
        RUNTIME_9P="0"
    fi
fi

# Detect and configure disks
detect_disks

# Set up Podman storage (Podman-specific)
setup_podman_storage

# Mount input disk
mount_input_disk

# Configure networking
configure_networking

# Verify podman is available (no daemon to start)
verify_podman

# Install user-supplied auth config from the dedicated auth 9p share, if any.
# Done before command execution so pulls/logins have credentials available.
install_auth_config

# Handle daemon mode or single command execution
if [ "$RUNTIME_DAEMON" = "1" ]; then
    run_daemon_mode
else
    prepare_input_path
    execute_command
fi

# Graceful shutdown
graceful_shutdown
