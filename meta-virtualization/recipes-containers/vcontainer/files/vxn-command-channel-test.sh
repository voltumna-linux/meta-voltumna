#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vxn-command-channel-test.sh  --  L0 architectural test for phase-3 vxn
# ===========================================================================
# Tests vxn-command-channel.sh (the dom0 responder) in isolation, with NO VM
# and NO Xen boot -- instant feedback on the riskiest new piece of phase 3.
#
# A `socat UNIX-LISTEN` bridge stands in for QEMU's virtio-serial chardev
# socket; the test client speaks the exact protocol vrunner.sh:daemon_send()
# uses (send base64 command, read ===OUTPUT_START/END===, ===EXIT_CODE=N===,
# ===END===). If this passes, the responder will interoperate with the reused
# host-side daemon machinery.
#
# Usage:  bash vxn-command-channel-test.sh
# Exit:   0 = all pass, 1 = a failure (prints which).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESPONDER="${1:-$SCRIPT_DIR/vxn-command-channel.sh}"

command -v socat  >/dev/null || { echo "SKIP: socat not installed"; exit 2; }
command -v base64 >/dev/null || { echo "SKIP: base64 not installed"; exit 2; }
[ -f "$RESPONDER" ] || { echo "FAIL: responder not found: $RESPONDER"; exit 1; }

TMPD="$(mktemp -d)"
SOCK="$TMPD/cc.sock"
trap 'kill "$SOCAT_PID" 2>/dev/null; rm -rf "$TMPD"' EXIT

# socat forks a fresh responder per connection (fork), mirroring how a client
# reconnects to the persistent QEMU chardev per command.
socat "UNIX-LISTEN:$SOCK,fork" EXEC:"/bin/sh $RESPONDER" &
SOCAT_PID=$!

# Wait for the listener socket to appear.
for _ in $(seq 1 50); do [ -S "$SOCK" ] && break; sleep 0.1; done
[ -S "$SOCK" ] || { echo "FAIL: socat listener never came up"; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL: $1"; echo "        $2"; }

# --- protocol client: mirrors vrunner.sh daemon_send() ---------------------
# Sends one line (raw marker, or a base64 command) and captures the response.
# Populates: R_OUT (text between OUTPUT_START/END), R_EC (exit code),
# R_RAW (all response lines), R_TERM (terminal marker seen).
exchange() {
    local send_line="$1"
    R_OUT=""; R_EC=""; R_RAW=""; R_TERM=""
    local in_out=false line
    coproc CONN { socat - "UNIX-CONNECT:$SOCK" 2>/dev/null; }
    printf '%s\n' "$send_line" >&"${CONN[1]}"
    while IFS= read -t 5 -r line <&"${CONN[0]}"; do
        R_RAW="${R_RAW}${line}"$'\n'
        case "$line" in
            "===OUTPUT_START===") in_out=true ;;
            "===OUTPUT_END===")   in_out=false ;;
            "===EXIT_CODE="*"===") R_EC="${line#===EXIT_CODE=}"; R_EC="${R_EC%===}" ;;
            "===END===")          R_TERM="END"; break ;;
            "===SHUTTING_DOWN===") R_TERM="SHUTDOWN"; break ;;
            *) [ "$in_out" = true ] && R_OUT="${R_OUT:+$R_OUT$'\n'}$line" ;;
        esac
    done
    eval "exec ${CONN[1]}>&- ${CONN[0]}<&-" 2>/dev/null || true
    kill "$CONN_PID" 2>/dev/null; wait "$CONN_PID" 2>/dev/null || true
}

# base64-encode a command the way daemon_send does, and exchange it.
run_cmd() { exchange "$(printf '%s' "$1" | base64 -w0)"; }

echo "L0 vxn-command-channel test  (responder: $RESPONDER)"

# 1. simple command, stdout + exit 0
run_cmd 'echo hi'
[ "$R_OUT" = "hi" ] && [ "$R_EC" = "0" ] \
    && ok "echo hi -> 'hi', exit 0" \
    || bad "echo hi" "R_OUT='$R_OUT' R_EC='$R_EC'"

# 2. non-zero exit code is propagated
run_cmd 'echo oops; exit 3'
[ "$R_OUT" = "oops" ] && [ "$R_EC" = "3" ] \
    && ok "exit code 3 propagated" \
    || bad "exit code" "R_OUT='$R_OUT' R_EC='$R_EC'"

# 3. multi-line output preserved
run_cmd 'printf "a\nb\nc\n"'
[ "$R_OUT" = $'a\nb\nc' ] \
    && ok "multi-line output preserved" \
    || bad "multi-line" "R_OUT='$R_OUT'"

# 4. stderr is captured (2>&1 in the responder)
run_cmd 'echo to-stderr 1>&2; exit 0'
[ "$R_OUT" = "to-stderr" ] \
    && ok "stderr captured into output" \
    || bad "stderr" "R_OUT='$R_OUT'"

# 5. PING -> PONG (control marker, not base64)
exchange '===PING==='
case "$R_RAW" in *"===PONG==="*) ok "PING -> PONG" ;; *) bad "PING" "R_RAW='$R_RAW'" ;; esac

# 6. malformed (non-base64) input -> exit 1 + error text, not a hang
exchange 'this-is-not-base64-@@@'
{ [ "$R_EC" = "1" ] && [ "$R_TERM" = "END" ]; } \
    && ok "malformed input -> exit 1, clean END" \
    || bad "malformed input" "R_EC='$R_EC' R_TERM='$R_TERM'"

# 7. SHUTDOWN -> SHUTTING_DOWN
exchange '===SHUTDOWN==='
[ "$R_TERM" = "SHUTDOWN" ] \
    && ok "SHUTDOWN -> SHUTTING_DOWN" \
    || bad "SHUTDOWN" "R_RAW='$R_RAW'"

echo
echo "L0 result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
