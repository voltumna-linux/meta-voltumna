#!/bin/bash
# Helper script to manage memres for the test state directory.
#
# Usage:
#   ./memres-test.sh start [--vdkr-dir /path/to/vdkr] [--arch x86_64|aarch64]
#   ./memres-test.sh stop  [--vdkr-dir /path/to/vdkr] [--arch x86_64|aarch64]
#   ./memres-test.sh status [--vdkr-dir /path/to/vdkr] [--arch x86_64|aarch64]

set -e

# Defaults
VDKR_DIR="${VDKR_STANDALONE_DIR:-/tmp/vdkr-standalone}"
ARCH="${VDKR_ARCH:-x86_64}"
TEST_STATE_DIR="$HOME/.vdkr-test"

# Parse arguments
CMD=""
while [[ $# -gt 0 ]]; do
    case $1 in
        start|stop|status)
            CMD="$1"
            shift
            ;;
        --vdkr-dir)
            VDKR_DIR="$2"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$CMD" ]; then
    echo "Usage: $0 start|stop|status [--vdkr-dir PATH] [--arch x86_64|aarch64]" >&2
    exit 1
fi

# Validate vdkr directory
if [ ! -d "$VDKR_DIR" ]; then
    echo "Error: vdkr directory not found: $VDKR_DIR" >&2
    echo "Set VDKR_STANDALONE_DIR or use --vdkr-dir" >&2
    exit 1
fi

# Source environment
if [ -f "$VDKR_DIR/init-env.sh" ]; then
    source "$VDKR_DIR/init-env.sh"
elif [ -f "$VDKR_DIR/setup-env.sh" ]; then
    source "$VDKR_DIR/setup-env.sh"
fi

# Find vdkr binary - try symlink first, then main vdkr with --arch
VDKR_BIN="$VDKR_DIR/vdkr-$ARCH"
VDKR_ARGS=""
if [ ! -x "$VDKR_BIN" ]; then
    # Try main vdkr binary with --arch flag
    VDKR_BIN="$VDKR_DIR/vdkr"
    VDKR_ARGS="--arch $ARCH"
    if [ ! -x "$VDKR_BIN" ]; then
        echo "Error: vdkr binary not found: $VDKR_DIR/vdkr or $VDKR_DIR/vdkr-$ARCH" >&2
        exit 1
    fi
fi

STATE_DIR="$TEST_STATE_DIR/$ARCH"

case "$CMD" in
    start)
        echo "Starting memres for tests (state: $STATE_DIR)..."
        "$VDKR_BIN" $VDKR_ARGS --state-dir "$STATE_DIR" memres start
        echo "Memres started. Run tests with:"
        echo "  pytest tests/test_vdkr.py -v --vdkr-dir $VDKR_DIR --arch $ARCH --skip-destructive"
        ;;
    stop)
        echo "Stopping memres for tests..."
        "$VDKR_BIN" $VDKR_ARGS --state-dir "$STATE_DIR" memres stop
        ;;
    status)
        "$VDKR_BIN" $VDKR_ARGS --state-dir "$STATE_DIR" memres status
        ;;
esac
