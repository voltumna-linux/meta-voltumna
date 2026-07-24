#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
# SPDX-License-Identifier: MIT
#
# container-registry.sh
# ============================================
# Helper script to start/stop a local container registry
# ============================================
#
# This script manages a local docker-distribution registry server
# for development purposes.
#
# Usage:
#   container-registry.sh start [config.yml] [storage-dir]
#   container-registry.sh stop
#   container-registry.sh status
#   container-registry.sh logs
#
# Examples:
#   # Start with defaults (port 5000, storage in /tmp/container-registry)
#   container-registry.sh start
#
#   # Start with custom config
#   container-registry.sh start /path/to/config.yml
#
#   # Start with custom storage
#   container-registry.sh start /path/to/config.yml /var/lib/registry
#
# Environment:
#   REGISTRY_BIN     Path to registry binary (auto-detected from oe-run-native)
#   REGISTRY_CONFIG  Path to config file
#   REGISTRY_STORAGE Storage directory
#   REGISTRY_PORT    Port to listen on (default: 5000)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="/tmp/container-registry.pid"
LOG_FILE="/tmp/container-registry.log"

# Default configuration
REGISTRY_PORT="${REGISTRY_PORT:-5000}"
REGISTRY_STORAGE="${REGISTRY_STORAGE:-/tmp/container-registry}"

# Find registry binary
find_registry_bin() {
    # Check if provided via environment
    if [ -n "$REGISTRY_BIN" ] && [ -x "$REGISTRY_BIN" ]; then
        echo "$REGISTRY_BIN"
        return 0
    fi

    # Try to find in Yocto native sysroot
    local builddir="${BUILDDIR:-$(pwd)}"
    local native_sysroot="$builddir/tmp/work/x86_64-linux/docker-distribution-native"

    if [ -d "$native_sysroot" ]; then
        local registry=$(find "$native_sysroot" -name "registry" -type f -executable 2>/dev/null | head -1)
        if [ -n "$registry" ]; then
            echo "$registry"
            return 0
        fi
    fi

    # Try system PATH
    if command -v registry &>/dev/null; then
        command -v registry
        return 0
    fi

    return 1
}

# Find config file
find_config() {
    local config="$1"

    if [ -n "$config" ] && [ -f "$config" ]; then
        echo "$config"
        return 0
    fi

    # Check environment
    if [ -n "$REGISTRY_CONFIG" ] && [ -f "$REGISTRY_CONFIG" ]; then
        echo "$REGISTRY_CONFIG"
        return 0
    fi

    # Check script directory
    if [ -f "$SCRIPT_DIR/container-registry-dev.yml" ]; then
        echo "$SCRIPT_DIR/container-registry-dev.yml"
        return 0
    fi

    return 1
}

cmd_start() {
    local config="$1"
    local storage="${2:-$REGISTRY_STORAGE}"

    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Registry already running (PID: $pid)"
            return 1
        fi
        rm -f "$PID_FILE"
    fi

    local registry_bin
    if ! registry_bin=$(find_registry_bin); then
        echo "Error: Cannot find registry binary"
        echo "Build it with: bitbake docker-distribution-native"
        return 1
    fi

    local config_file
    if ! config_file=$(find_config "$config"); then
        echo "Error: Cannot find config file"
        echo "Provide config file as argument or set REGISTRY_CONFIG"
        return 1
    fi

    # Create storage directory
    mkdir -p "$storage"

    echo "Starting container registry..."
    echo "  Binary:  $registry_bin"
    echo "  Config:  $config_file"
    echo "  Storage: $storage"
    echo "  Port:    $REGISTRY_PORT"

    # Export storage directory for config
    export REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY="$storage"

    # Start registry in background
    nohup "$registry_bin" serve "$config_file" > "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"

    # Wait for startup
    sleep 2

    if kill -0 "$pid" 2>/dev/null; then
        echo "Registry started (PID: $pid)"
        echo "Access at: http://localhost:$REGISTRY_PORT"
        echo "Logs at: $LOG_FILE"
    else
        echo "Failed to start registry. Check logs: $LOG_FILE"
        cat "$LOG_FILE"
        return 1
    fi
}

cmd_stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo "Registry not running (no PID file)"
        return 0
    fi

    local pid=$(cat "$PID_FILE")

    if kill -0 "$pid" 2>/dev/null; then
        echo "Stopping registry (PID: $pid)..."
        kill "$pid"
        sleep 2

        if kill -0 "$pid" 2>/dev/null; then
            echo "Force killing..."
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi

    rm -f "$PID_FILE"
    echo "Registry stopped"
}

cmd_status() {
    if [ ! -f "$PID_FILE" ]; then
        echo "Registry not running"
        return 1
    fi

    local pid=$(cat "$PID_FILE")

    if kill -0 "$pid" 2>/dev/null; then
        echo "Registry running (PID: $pid)"
        echo "Port: $REGISTRY_PORT"

        # Check if responding
        if curl -s "http://localhost:$REGISTRY_PORT/v2/" >/dev/null 2>&1; then
            echo "Status: healthy"

            # List images
            local catalog=$(curl -s "http://localhost:$REGISTRY_PORT/v2/_catalog" 2>/dev/null)
            if [ -n "$catalog" ]; then
                echo "Catalog: $catalog"
            fi
        else
            echo "Status: not responding"
        fi
    else
        echo "Registry not running (stale PID file)"
        rm -f "$PID_FILE"
        return 1
    fi
}

cmd_logs() {
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        echo "No log file found"
        return 1
    fi
}

cmd_help() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
  start [config] [storage]  Start the registry
  stop                      Stop the registry
  status                    Show registry status
  logs                      Tail registry logs
  help                      Show this help

Environment:
  REGISTRY_BIN     Path to registry binary
  REGISTRY_CONFIG  Path to config file
  REGISTRY_STORAGE Storage directory (default: /tmp/container-registry)
  REGISTRY_PORT    Port to listen on (default: 5000)
  BUILDDIR         Yocto build directory (for finding native binaries)

Examples:
  $(basename "$0") start
  $(basename "$0") start /path/to/config.yml
  $(basename "$0") status
  $(basename "$0") stop
EOF
}

# Main
case "${1:-help}" in
    start)
        cmd_start "$2" "$3"
        ;;
    stop)
        cmd_stop
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        echo "Unknown command: $1"
        cmd_help
        exit 1
        ;;
esac
