#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vpm: run dom0's container engine (docker by default) from the host over ssh.
# ===========================================================================
# Drive dom0's container engine (docker or podman -- both run there with vxn as
# their default runtime) from the host, without remembering the ssh key / port /
# TMPDIR incantation. One script; the engine is chosen by the invoked name
# (vpm -> podman, vdk -> docker) or VXN_ENGINE:
#
#   vpm images
#   sudo docker save claude-demo | vpm load
#   vpm run -it -e ANTHROPIC_API_KEY=$KEY claude-demo
#
# It mirrors how the `vxn` CLI proxies to dom0. Interactive (-it) gets a PTY;
# piped input (e.g. `docker save | vpm load`) stays raw. TMPDIR is pointed at
# dom0's disk-backed rootfs because dom0's /tmp and /var/tmp are small RAM
# tmpfs that image loads/builds overflow.
#
# Config (env): VXN_SSH_KEY (~/.vxn/id_vxn), VXN_SSH_PORT (18022),
#               VXN_DOM0_SCRATCH (/var/rh).

set -euo pipefail

KEY="${VXN_SSH_KEY:-$HOME/.vxn/id_vxn}"
PORT="${VXN_SSH_PORT:-18022}"
RTMP="${VXN_DOM0_SCRATCH:-/var/rh}/tmp"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Engine to drive in dom0, chosen by VXN_ENGINE, else the invoked name:
#   vctr  -> vctr  (ctr + the vxn runtime; containerd has no remote API, so it
#            must be proxied here rather than via a DOCKER_HOST-style env)
#   vpm   -> docker (the vexpose demo path, so `docker save | vpm load` lands
#            where `docker run` looks); VXN_ENGINE=podman to switch.
ENGINE="${VXN_ENGINE:-}"
if [ -z "$ENGINE" ]; then
    case "$(basename "$0")" in
        vctr) ENGINE="vctr" ;;     # containerd (ctr + vxn runtime)
        vpd)  ENGINE="podman" ;;   # podman in dom0 (for hosts without host podman)
        vdo)  ENGINE="docker" ;;   # docker in dom0 (for hosts without host docker)
        *)    ENGINE="docker" ;;   # vpm: docker in dom0 + the load helper
    esac
fi

declare -a OPTS=(-i "$KEY" -p "$PORT"
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR -o PasswordAuthentication=no -o IdentitiesOnly=yes
    -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4)

# Ensure dom0 is up (it holds the sshd we proxy to); auto-start it if not.
# NOTE: -n (stdin from /dev/null) on these checks is essential -- ssh forwards
# stdin to the remote by default, so without -n these connectivity probes would
# consume the piped payload (e.g. `docker save | vdk load`) and corrupt it
# ("invalid tar header"). Only the final exec ssh should read stdin.
if ! ssh -n "${OPTS[@]}" root@127.0.0.1 true 2>/dev/null; then
    echo "vpm: starting dom0..." >&2
    VXN="$SELF_DIR/vxn-$(uname -m)"; [ -x "$VXN" ] || VXN="$SELF_DIR/vxn"
    [ -x "$VXN" ] && "$VXN" vmemres start >/dev/null 2>&1 </dev/null || true
    for _ in $(seq 1 60); do ssh -n "${OPTS[@]}" root@127.0.0.1 true 2>/dev/null && break; sleep 2; done
    ssh -n "${OPTS[@]}" root@127.0.0.1 true 2>/dev/null || {
        echo "vpm: cannot reach dom0 over ssh (is 'vxn vmemres start' working?)" >&2; exit 1; }
fi

# `vpm push <local-file> <dom0-dest>`: hot-copy a file into the running dom0
# (dev convenience -- update a runtime/init script in place without a rebuild).
# Not an engine command; plain ssh, chmod +x on arrival.
if [ "${1:-}" = "push" ]; then
    [ $# -eq 3 ] && [ -f "$2" ] || { echo "usage: vpm push <local-file> <dom0-dest-path>" >&2; exit 1; }
    # mkdir -p the dest parent -- pushes into nested trees (e.g. the inject dir
    # /var/lib/vxn-inject/root/.claude/settings.json) would otherwise fail on a
    # missing parent. chmod +x is harmless on data files and wanted for scripts.
    ssh "${OPTS[@]}" root@127.0.0.1 "mkdir -p \"\$(dirname '$3')\" && cat > '$3' && chmod +x '$3'" < "$2" \
        && echo "vpm: pushed $2 -> dom0:$3" >&2
    exit $?
fi

# Allocate a PTY for interactive commands: an explicit -it/-t flag, OR a
# fully-interactive terminal on both ends -- the latter covers subcommands with
# no flag like `vctr task attach <id>` and `... exec`. Piped I/O (e.g.
# `docker save | vpm load`, `vpm images | grep`) has a non-tty end, so it stays
# raw and the binary/text stream isn't corrupted by a PTY.
tt=""
for a in "$@"; do case "$a" in -it|-ti|-i|-t|--interactive|--tty) tt="-tt" ;; esac; done
[ -z "$tt" ] && [ -t 0 ] && [ -t 1 ] && tt="-tt"

# Quote each arg for the single remote shell parse.
remote=""
for a in "$@"; do remote+=" $(printf '%q' "$a")"; done

exec ssh $tt "${OPTS[@]}" root@127.0.0.1 "mkdir -p $RTMP 2>/dev/null; TMPDIR=$RTMP $ENGINE$remote"
