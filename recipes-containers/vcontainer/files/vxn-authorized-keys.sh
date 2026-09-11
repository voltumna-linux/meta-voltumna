#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vxn-authorized-keys.sh
# ===========================================================================
# dom0-side installer for the SDK's ssh public key.
#
# Interactive containers (`vxn -it run ... sh`) can't ride the marker command
# channel (it isn't a PTY). The transparent SDK instead routes -it over
# `ssh -tt` to dom0's native vxn, which does the interactive work via
# `xl create -c`. For that ssh to be passwordless and non-interactive, the
# SDK's public key must be in root's authorized_keys. The host stages the
# pubkey onto a dedicated read-only 9p share (tag vxn_sshkey, see vrunner.sh
# setup_ssh_key_share); this installs it. dom0 boots fresh from the wic each
# time, so this runs every boot.

set -u

TAG="vxn_sshkey"
MNT="/run/vxn-sshkey"
DEST="/root/.ssh"

mkdir -p "$MNT"
if ! mount -t 9p -o trans=virtio,version=9p2000.L,cache=none,ro "$TAG" "$MNT" 2>/dev/null; then
    # No key share attached (interactive ssh not in use) -- nothing to do.
    rmdir "$MNT" 2>/dev/null || true
    exit 0
fi

if [ -f "$MNT/authorized_keys" ]; then
    mkdir -p "$DEST"
    chmod 700 "$DEST"
    # Merge rather than clobber (preserve any image-provided keys), then de-dup.
    # dom0 is ephemeral so this normally starts from empty; the merge is
    # defensive.
    touch "$DEST/authorized_keys"
    cat "$MNT/authorized_keys" >> "$DEST/authorized_keys"
    sort -u "$DEST/authorized_keys" > "$DEST/authorized_keys.tmp" 2>/dev/null \
        && mv "$DEST/authorized_keys.tmp" "$DEST/authorized_keys"
    chmod 600 "$DEST/authorized_keys"
    echo "vxn-authorized-keys: installed SDK ssh public key into root's authorized_keys"
fi

umount "$MNT" 2>/dev/null || umount -l "$MNT" 2>/dev/null || true
rmdir "$MNT" 2>/dev/null || true
