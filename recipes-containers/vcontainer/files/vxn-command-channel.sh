#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vxn-command-channel.sh
# ===========================================================================
# dom0-side command responder for the "qemu-xen" vxn backend.
#
# When vxn runs as a host CLI that boots a Xen dom0 inside QEMU (mode 1 /
# phase 3), the host proxies commands into this dom0 over a virtio-serial
# port. This responder reads base64-encoded commands from the channel and
# executes them in dom0, returning output using the vrunner marker protocol --
# the same protocol vrunner.sh:daemon_send() speaks, so the host side is
# reused unchanged.
#
# The command dispatched into dom0 is "vxn run ..." -- dom0's own front end,
# which turns it into a Xen PV DomU via skopeo + xl. (docker/podman are not
# involved: the host relays vxn commands, not docker ones.)
#
# Two modes:
#   * default (no --port): read stdin, write stdout. Used by the L0 socat
#     test harness (vxn-command-channel-test.sh) -- no VM required. EOF (the
#     client closing the connection) ends the responder.
#   * --port DEV: bind to a virtio-serial char device, held open
#     bidirectionally (exec 3<>DEV). The host reconnects per command
#     (daemon_send opens a fresh socket each time), so the port read sees EOF
#     between commands; we must KEEP SERVING across those disconnects and exit
#     only on ===SHUTDOWN===. This mirrors the proven guest-init loop in
#     vcontainer-init-common.sh (while-true read <&3, never exit on EOF).
#     Deployed by systemd:
#       ExecStart=/usr/bin/vxn-command-channel.sh --port /dev/virtio-ports/vdkr
#
# Protocol (matches vrunner.sh daemon_send + vxn-init.sh run_vxn_daemon_mode):
#   in  ===PING===        -> out ===PONG===
#       ===SHUTDOWN===    -> out ===SHUTTING_DOWN=== ; exit loop
#       <base64 command>  -> out ===OUTPUT_START=== <output> ===OUTPUT_END===
#                                ===EXIT_CODE=N=== ===END===
# On startup emits ===PONG=== as a readiness marker (host waits for it).

set -u

VXN_CC_SHELL="${VXN_CC_SHELL:-/bin/sh}"
PORT=""
# How long (seconds) to wait for --port to appear before giving up. Kept as a
# clean idle exit (0) so the systemd unit's Restart=on-failure does not spin on
# a plain boot where no vdkr port is attached.
PORT_WAIT="${VXN_CC_PORT_WAIT:-15}"

while [ $# -gt 0 ]; do
    case "$1" in
        --port)    PORT="$2"; shift 2 ;;
        --port=*)  PORT="${1#--port=}"; shift ;;
        --shell)   VXN_CC_SHELL="$2"; shift 2 ;;
        --shell=*) VXN_CC_SHELL="${1#--shell=}"; shift ;;
        *) echo "vxn-command-channel: unknown argument: $1" >&2; exit 2 ;;
    esac
done

# The command loop. Reads from stdin, writes to stdout; the caller wires those
# to the channel (a pipe in test mode, or fd 3<>PORT in deployment mode).
#
# $1 = EOF behavior:
#   "exit"  -> a read EOF means the client closed the connection; return.
#             (pipe / L0 test mode: socat forks a responder per connection.)
#   "serve" -> a read EOF just means the host disconnected between commands;
#             the virtio port stays open, so keep serving. Exit only on
#             ===SHUTDOWN===. A short sleep avoids a busy-loop if the port
#             signals EOF-on-disconnect rather than blocking the read.
cc_loop() {
    on_eof="${1:-exit}"

    # Readiness marker so the host knows the responder is up.
    echo "===PONG==="

    while true; do
        LINE=""
        if ! IFS= read -r LINE; then
            [ "$on_eof" = "exit" ] && return 0
            sleep 0.2
            continue
        fi

        [ -z "$LINE" ] && continue

        case "$LINE" in
            "===PING===")
                echo "===PONG==="
                continue
                ;;
            "===SHUTDOWN===")
                echo "===SHUTTING_DOWN==="
                return 0
                ;;
        esac

        # Everything else is a base64-encoded command to run in dom0. Reject
        # undecodable input explicitly (base64 -d exits non-zero) rather than
        # running the garbage bytes as a command.
        CMD=$(printf '%s' "$LINE" | base64 -d 2>/dev/null)
        DECODE_RC=$?
        if [ "$DECODE_RC" -ne 0 ] || [ -z "$CMD" ]; then
            echo "===OUTPUT_START==="
            echo "vxn-command-channel: failed to decode command"
            echo "===OUTPUT_END==="
            echo "===EXIT_CODE=1==="
            echo "===END==="
            continue
        fi

        # Run in dom0. stdin from /dev/null so the command can never consume
        # protocol bytes off the channel; stdout+stderr captured together.
        EXIT_CODE=0
        OUT_FILE=$(mktemp 2>/dev/null || echo "/tmp/.vxn-cc-out.$$")
        "$VXN_CC_SHELL" -c "$CMD" </dev/null > "$OUT_FILE" 2>&1 || EXIT_CODE=$?

        echo "===OUTPUT_START==="
        cat "$OUT_FILE"
        echo "===OUTPUT_END==="
        echo "===EXIT_CODE=$EXIT_CODE==="
        echo "===END==="
        rm -f "$OUT_FILE"
    done
}

if [ -n "$PORT" ]; then
    # Deployment mode: wait for the virtio-serial port, then hold it open
    # bidirectionally under this (long-lived) PID and serve across the host's
    # per-command reconnects.
    i=0
    while [ ! -e "$PORT" ] && [ "$i" -lt "$PORT_WAIT" ]; do
        i=$((i + 1))
        sleep 1
    done
    if [ ! -e "$PORT" ]; then
        echo "vxn-command-channel: port $PORT not present after ${PORT_WAIT}s; idle exit" >&2
        exit 0
    fi
    exec 3<>"$PORT" || {
        echo "vxn-command-channel: cannot open $PORT" >&2
        exit 1
    }
    cc_loop serve <&3 >&3
else
    # Test / pipe mode: stdin/stdout (see vxn-command-channel-test.sh, L0).
    cc_loop exit
fi
