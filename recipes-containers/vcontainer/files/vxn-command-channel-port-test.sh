#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vxn-command-channel-port-test.sh -- L2 transport test for phase-3 vxn
# ===========================================================================
# Exercises vxn-command-channel.sh in --port (deployment) mode over a REAL
# bidirectional character device: a PTY pair bridged by socat stands in for
# QEMU's virtio-serial port. This proves the systemd-deployment code path --
# `exec 3<>"$PORT"; cc_loop <&3 >&3` -- reads commands from and writes
# responses back to the same char device, and that multiple commands flow over
# ONE persistent connection (the guest-side invariant: the port fd is held open
# under a long-lived PID and never EOFs between commands).
#
# NOTE: this does NOT test host disconnect/reconnect survival -- that is
# specific to QEMU's chardev<->virtio buffering and is covered by the L3
# full-stack boot. Here both ends stay open for the whole session, which is the
# exact byte-stream the guest side sees.
#
# Instant-ish (spawns socat + the responder, no VM). Usage:
#   bash vxn-command-channel-port-test.sh
# Exit 0 = all pass.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESPONDER="${1:-$SCRIPT_DIR/vxn-command-channel.sh}"

command -v socat  >/dev/null || { echo "SKIP: socat not installed"; exit 2; }
command -v base64 >/dev/null || { echo "SKIP: base64 not installed"; exit 2; }
[ -f "$RESPONDER" ] || { echo "FAIL: responder not found: $RESPONDER"; exit 1; }

TMPD="$(mktemp -d)"
GUEST="$TMPD/vport-guest"     # the responder's --port (its /dev/virtio-ports/vdkr)
HOST="$TMPD/vport-host"       # the host end (QEMU chardev socket stand-in)
RESP_PID=""; SOCAT_PID=""
cleanup() {
    [ -n "$RESP_PID" ]  && kill "$RESP_PID"  2>/dev/null
    [ -n "$SOCAT_PID" ] && kill "$SOCAT_PID" 2>/dev/null
    exec 4>&- 2>/dev/null || true
    rm -rf "$TMPD"
}
trap cleanup EXIT

# Bridge two PTYs: bytes on GUEST appear on HOST and vice versa. Each is a real
# tty char device -- the same device *class* the responder opens in dom0.
socat PTY,raw,echo=0,link="$GUEST" PTY,raw,echo=0,link="$HOST" &
SOCAT_PID=$!
for _ in $(seq 1 50); do [ -e "$GUEST" ] && [ -e "$HOST" ] && break; sleep 0.1; done
{ [ -e "$GUEST" ] && [ -e "$HOST" ]; } || { echo "FAIL: PTY bridge never came up"; exit 1; }

# Start the responder bound to the guest PTY (deployment mode).
/bin/sh "$RESPONDER" --port "$GUEST" &
RESP_PID=$!

# Open the host end persistently (one connection for the whole session).
exec 4<>"$HOST"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; echo "        $2"; }

# Read response lines from fd 4 until a terminal marker. Sets R_OUT/R_EC/R_TERM.
read_response() {
    R_OUT=""; R_EC=""; R_TERM=""
    local in_out=false line
    while IFS= read -t 8 -r line <&4; do
        line="${line%$'\r'}"                 # PTY may append CR
        case "$line" in
            "===OUTPUT_START===")  in_out=true ;;
            "===OUTPUT_END===")    in_out=false ;;
            "===EXIT_CODE="*"===") R_EC="${line#===EXIT_CODE=}"; R_EC="${R_EC%===}" ;;
            "===END===")           R_TERM="END"; return ;;
            "===SHUTTING_DOWN===") R_TERM="SHUTDOWN"; return ;;
            "===PONG===")          R_TERM="PONG"; return ;;
            *) [ "$in_out" = true ] && R_OUT="${R_OUT:+$R_OUT$'\n'}$line" ;;
        esac
    done
    R_TERM="TIMEOUT"
}
send() { printf '%s\n' "$1" >&4; }
send_cmd() { send "$(printf '%s' "$1" | base64 -w0)"; read_response; }

echo "L2 port-mode transport test  (responder: $RESPONDER)"

# 0. readiness: the responder emits ===PONG=== on the port at startup.
read_response
[ "$R_TERM" = "PONG" ] \
    && ok "startup readiness ===PONG=== on the port" \
    || bad "readiness" "R_TERM='$R_TERM'"

# 1. command over the real char device
send_cmd 'echo hi'
{ [ "$R_OUT" = "hi" ] && [ "$R_EC" = "0" ]; } \
    && ok "echo hi over PTY -> 'hi', exit 0" \
    || bad "echo hi" "R_OUT='$R_OUT' R_EC='$R_EC' R_TERM='$R_TERM'"

# 2. SECOND command on the SAME persistent connection (stream continuity)
send_cmd 'echo second; exit 5'
{ [ "$R_OUT" = "second" ] && [ "$R_EC" = "5" ]; } \
    && ok "second command on same stream (exit 5)" \
    || bad "second command" "R_OUT='$R_OUT' R_EC='$R_EC' R_TERM='$R_TERM'"

# 3. command cannot steal protocol bytes off the channel (stdin = /dev/null).
#    'cat' would otherwise block reading the port and desync everything.
send_cmd 'cat; echo after-cat'
{ [ "$R_OUT" = "after-cat" ] && [ "$R_EC" = "0" ]; } \
    && ok "command stdin isolated from channel (cat does not hang)" \
    || bad "stdin isolation" "R_OUT='$R_OUT' R_EC='$R_EC' R_TERM='$R_TERM'"

# 4. PING mid-stream
send '===PING==='
read_response
[ "$R_TERM" = "PONG" ] \
    && ok "PING mid-stream -> PONG" \
    || bad "PING" "R_TERM='$R_TERM'"

# 5. THIRD command after the PING (still in sync)
send_cmd 'printf "x\ny\n"'
[ "$R_OUT" = $'x\ny' ] \
    && ok "still in sync after PING (multi-line)" \
    || bad "post-ping sync" "R_OUT='$R_OUT' R_TERM='$R_TERM'"

# 6. SHUTDOWN ends the loop
send '===SHUTDOWN==='
read_response
[ "$R_TERM" = "SHUTDOWN" ] \
    && ok "SHUTDOWN -> SHUTTING_DOWN" \
    || bad "SHUTDOWN" "R_TERM='$R_TERM'"

echo
echo "L2 result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
