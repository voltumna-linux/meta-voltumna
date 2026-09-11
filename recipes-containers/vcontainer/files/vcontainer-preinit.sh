#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vcontainer-preinit.sh
# Minimal init for initramfs - mounts rootfs and does switch_root
#
# This script runs from the initramfs and:
# 1. Mounts essential filesystems
# 2. Finds and mounts the rootfs.img (squashfs, read-only)
# 3. Creates overlayfs with tmpfs for writes
# 4. Executes switch_root to the overlay root filesystem
#
# The real init (/init or /sbin/init on rootfs) then continues boot

# Mount essential filesystems first (needed to check cmdline)
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Check for quiet mode, block device prefix, and init script selection
QUIET=0
BLK_PREFIX="vd"
INIT_SCRIPT="/init"
for param in $(cat /proc/cmdline 2>/dev/null); do
    case "$param" in
        docker_interactive=1) QUIET=1 ;;
        vcontainer.blk=*) BLK_PREFIX="${param#vcontainer.blk=}" ;;
        vcontainer.init=*) INIT_SCRIPT="${param#vcontainer.init=}" ;;
    esac
done

log() {
    [ "$QUIET" = "0" ] && echo "$@"
}

# Boot-flow timing (opt-in via `vcontainer_timing` on the kernel cmdline).
# Echoes uptime at each stage to the console -- these are USERSPACE writes, so
# they bypass quiet/loglevel and land in the runner's captured vm_output.txt
# (use `vxn run --keep-temp`, then grep VXNTIME /tmp/vdkr-*/vm_output.txt).
# The first stamp (preinit:start) = time from domain create to userspace, i.e.
# kernel decompress + init + initramfs unpack.
_VXN_TIMING=0
case " $(cat /proc/cmdline 2>/dev/null) " in *" vcontainer_timing"*) _VXN_TIMING=1 ;; esac
# Buffer preinit stamps (the initramfs is thrown away at switch_root); flushed to
# /mnt/root/run/vxntiming just before switch_root so vxn-init inherits them and
# prints the whole timeline in the run OUTPUT.
_TSBUF=""
_ts() { [ "$_VXN_TIMING" = "1" ] && _TSBUF="${_TSBUF}VXNTIME preinit:$1 $(cut -d' ' -f1 /proc/uptime)
"; }
_ts start

# Suppress kernel console messages in interactive mode so they don't
# pollute the terminal (loop device messages bypass loglevel=0)
[ "$QUIET" = "1" ] && { dmesg -n 1 2>/dev/null || true; }

log "=== vcontainer preinit (squashfs) ==="

# The rootfs.img is always the first block device
# QEMU: /dev/vda, Xen: /dev/xvda
ROOTFS_DEV="/dev/${BLK_PREFIX}a"

# Wait for the rootfs device to appear. Under Xen PV/PVH the blkfront device
# shows up within tens of ms of the xenbus probe, so poll fast instead of a
# blind fixed sleep (was: sleep 2). Bounded to ~3s so a genuinely missing
# device still falls through to the error path below rather than hanging.
log "Waiting for block devices..."
_i=0
while [ ! -b "$ROOTFS_DEV" ] && [ "$_i" -lt 300 ]; do
    sleep 0.01
    _i=$((_i + 1))
done
_ts rootdev

# Show available block devices
log "Block devices:"
[ "$QUIET" = "0" ] && ls -la /dev/${BLK_PREFIX}* 2>/dev/null || log "No /dev/${BLK_PREFIX}* block devices found"

if [ ! -b "$ROOTFS_DEV" ]; then
    echo "ERROR: Rootfs device $ROOTFS_DEV not found!"
    echo "Available devices:"
    ls -la /dev/
    sleep 10
    reboot -f
fi

# Create mount points for overlay setup
mkdir -p /mnt/lower    # squashfs (read-only)
mkdir -p /mnt/upper    # tmpfs for overlay upper
mkdir -p /mnt/work     # tmpfs for overlay work
mkdir -p /mnt/root     # final overlayfs mount

# Mount squashfs read-only
log "Mounting squashfs rootfs from $ROOTFS_DEV..."

if ! mount -t squashfs -o ro "$ROOTFS_DEV" /mnt/lower; then
    # Fallback to ext4 for backwards compatibility
    log "squashfs mount failed, trying ext4..."
    if ! mount -t ext4 -o ro "$ROOTFS_DEV" /mnt/lower; then
        echo "ERROR: Failed to mount rootfs (tried squashfs and ext4)!"
        sleep 10
        reboot -f
    fi
    # ext4 fallback - just use it directly without overlay
    log "Using ext4 rootfs directly (no overlay)"
    mount --move /mnt/lower /mnt/root
else
    log "Squashfs mounted successfully"

    # Create tmpfs for overlay upper/work directories
    # Size is generous since container operations need temp space
    log "Creating tmpfs overlay..."
    mount -t tmpfs -o size=1G tmpfs /mnt/upper
    mkdir -p /mnt/upper/upper
    mkdir -p /mnt/upper/work

    # Create overlayfs combining squashfs (lower) + tmpfs (upper)
    log "Mounting overlayfs..."
    if ! mount -t overlay overlay -o lowerdir=/mnt/lower,upperdir=/mnt/upper/upper,workdir=/mnt/upper/work /mnt/root; then
        echo "ERROR: Failed to mount overlayfs!"
        sleep 10
        reboot -f
    fi

    log "Overlayfs mounted successfully"
fi
_ts rootfs_mounted

if [ "$QUIET" = "0" ]; then
    echo "Contents:"
    ls -la /mnt/root/
fi

# Verify init exists on rootfs
if [ ! -x /mnt/root/init ] && [ ! -x /mnt/root/sbin/init ]; then
    echo "ERROR: No init found on rootfs!"
    sleep 10
    reboot -f
fi

# Move filesystems to new root before switch_root
# This way they persist across switch_root and the new init doesn't need to remount
mkdir -p /mnt/root/proc /mnt/root/sys /mnt/root/dev
mount --move /proc /mnt/root/proc
mount --move /sys /mnt/root/sys
mount --move /dev /mnt/root/dev

# Switch to real root
# switch_root will:
# 1. Mount the new root
# 2. chroot into it
# 3. Execute the new init
# 4. Delete everything in the old initramfs
log "Switching to real root (init: $INIT_SCRIPT)..."
_ts switch_root
# Hand the preinit stamps to the real root so vxn-init can print them.
[ "$_VXN_TIMING" = "1" ] && { printf '%s' "$_TSBUF" > /mnt/root/vxntiming; }

if [ -x "/mnt/root${INIT_SCRIPT}" ]; then
    exec switch_root /mnt/root "$INIT_SCRIPT"
elif [ -x /mnt/root/init ]; then
    log "WARNING: $INIT_SCRIPT not found, falling back to /init"
    exec switch_root /mnt/root /init
elif [ -x /mnt/root/sbin/init ]; then
    exec switch_root /mnt/root /sbin/init
fi

# If we get here, switch_root failed
echo "ERROR: switch_root failed!"
sleep 10
reboot -f
