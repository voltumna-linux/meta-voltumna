#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vxn-host-certs.sh
# ===========================================================================
# dom0-side installer for host-provided corporate CA certificate(s).
#
# Behind a TLS-intercepting corporate proxy (e.g. Zscaler), dom0's skopeo/docker
# image pulls from docker.io fail with "x509: certificate signed by unknown
# authority" because dom0 doesn't trust the proxy's root CA. The host stages the
# CA(s) onto a dedicated read-only 9p share (see vrunner.sh setup_ca_share); this
# installs them into dom0's SYSTEM trust store -- the native way an OS admin adds
# a corporate root CA -- so pulls succeed. dom0 boots fresh from the wic each
# time, so this runs every boot.
#
# The certs are also left in /usr/local/share/ca-certificates so the Xen backend
# can inject them into each DomU's rootfs (so containers that do their own TLS
# inherit dom0's trust -- see vrunner-backend-xen.sh / vxn-init.sh).

set -u

TAG="vxn_ca"
MNT="/run/vxn-ca"
DEST="/usr/local/share/ca-certificates"

mkdir -p "$MNT"
if ! mount -t 9p -o trans=virtio,version=9p2000.L,cache=none,ro "$TAG" "$MNT" 2>/dev/null; then
    # No CA share attached (user provided no certs) -- nothing to do.
    rmdir "$MNT" 2>/dev/null || true
    exit 0
fi

n=0
mkdir -p "$DEST"
for f in "$MNT"/*.crt; do
    [ -f "$f" ] || continue
    if cp "$f" "$DEST/$(basename "$f")"; then
        n=$((n + 1))
    fi
done

umount "$MNT" 2>/dev/null || umount -l "$MNT" 2>/dev/null || true
rmdir "$MNT" 2>/dev/null || true

if [ "$n" -gt 0 ]; then
    update-ca-certificates >/dev/null 2>&1
    echo "vxn-host-certs: installed $n host CA certificate(s) into the dom0 trust store"
fi
