#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vcontainer-common.sh: Shared code for vdkr and vpdmn CLI wrappers
#
# This file is sourced by vdkr.sh and vpdmn.sh after they set:
#   VCONTAINER_RUNTIME_NAME   - Tool name (vdkr or vpdmn)
#   VCONTAINER_RUNTIME_CMD    - Container command (docker or podman)
#   VCONTAINER_RUNTIME_PREFIX - Env var prefix (VDKR or VPDMN)
#   VCONTAINER_IMPORT_TARGET  - skopeo target (docker-daemon: or containers-storage:)
#   VCONTAINER_STATE_FILE     - State image name (docker-state.img or podman-state.img)
#   VCONTAINER_OTHER_PREFIX   - Other tool's prefix for orphan checking (VPDMN or VDKR)
#   VCONTAINER_VERSION        - Tool version

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate required variables are set
: "${VCONTAINER_RUNTIME_NAME:?VCONTAINER_RUNTIME_NAME must be set}"
: "${VCONTAINER_RUNTIME_CMD:?VCONTAINER_RUNTIME_CMD must be set}"
: "${VCONTAINER_RUNTIME_PREFIX:?VCONTAINER_RUNTIME_PREFIX must be set}"
: "${VCONTAINER_IMPORT_TARGET:?VCONTAINER_IMPORT_TARGET must be set}"
: "${VCONTAINER_STATE_FILE:?VCONTAINER_STATE_FILE must be set}"
: "${VCONTAINER_OTHER_PREFIX:?VCONTAINER_OTHER_PREFIX must be set}"
: "${VCONTAINER_VERSION:?VCONTAINER_VERSION must be set}"

# ============================================================================
# Configuration Management
# ============================================================================
# Config directory can be set via:
#   1. --config-dir command line option
#   2. ${VCONTAINER_RUNTIME_PREFIX}_CONFIG_DIR environment variable
#   3. Default: ~/.config/${VCONTAINER_RUNTIME_NAME}
#
# Config file format: key=value (one per line)
# Supported keys: arch, timeout, state-dir, verbose, idle-timeout, auto-daemon
# ============================================================================

# Pre-parse --config-dir from command line (needs to happen before detect_default_arch)
_preparse_config_dir() {
    local i=1
    while [ $i -le $# ]; do
        local arg="${!i}"
        case "$arg" in
            --config-dir)
                i=$((i + 1))
                echo "${!i}"
                return
                ;;
            --config-dir=*)
                echo "${arg#--config-dir=}"
                return
                ;;
        esac
        i=$((i + 1))
    done
    echo ""
}

_PREPARSE_CONFIG_DIR=$(_preparse_config_dir "$@")

# Get environment variable value dynamically
_get_env_var() {
    local var_name="${VCONTAINER_RUNTIME_PREFIX}_$1"
    echo "${!var_name}"
}

CONFIG_DIR="${_PREPARSE_CONFIG_DIR:-$(_get_env_var CONFIG_DIR)}"
[ -z "$CONFIG_DIR" ] && CONFIG_DIR="$HOME/.config/$VCONTAINER_RUNTIME_NAME"
CONFIG_FILE="$CONFIG_DIR/config"

# Read a config value
# Usage: config_get <key> [default]
config_get() {
    local key="$1"
    local default="$2"

    if [ -f "$CONFIG_FILE" ]; then
        local value=$(grep "^${key}=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')
        if [ -n "$value" ]; then
            echo "$value"
            return
        fi
    fi
    echo "$default"
}

# Write a config value
# Usage: config_set <key> <value>
config_set() {
    local key="$1"
    local value="$2"

    mkdir -p "$CONFIG_DIR"

    if [ -f "$CONFIG_FILE" ]; then
        # Remove existing key
        grep -v "^${key}=" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" 2>/dev/null || true
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi

    # Add new value
    echo "${key}=${value}" >> "$CONFIG_FILE"
}

# Remove a config value
# Usage: config_unset <key>
config_unset() {
    local key="$1"

    if [ -f "$CONFIG_FILE" ]; then
        grep -v "^${key}=" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" 2>/dev/null || true
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
}

# List all config values
config_list() {
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    fi
}

# Get config default value
config_default() {
    local key="$1"
    case "$key" in
        arch)         uname -m ;;
        timeout)      echo "300" ;;
        state-dir)    echo "$HOME/.$VCONTAINER_RUNTIME_NAME" ;;
        verbose)      echo "false" ;;
        idle-timeout) echo "1800" ;;   # 30 minutes
        auto-daemon)  echo "true" ;;   # Auto-start daemon by default
        registry)     echo "" ;;       # Default registry for unqualified images
        *)            echo "" ;;
    esac
}

# ============================================================================
# Architecture Detection
# ============================================================================
# Priority order:
# 1. --arch / -a command line flag (parsed below)
# 2. Executable name: ${name}-aarch64 -> aarch64, ${name}-x86_64 -> x86_64
# 3. ${PREFIX}_ARCH environment variable
# 4. Config file: $CONFIG_DIR/config (arch key)
# 5. Legacy config file: $CONFIG_DIR/arch (for backwards compatibility)
# 6. Host architecture (uname -m)
# ============================================================================

detect_arch_from_name() {
    local prog_name=$(basename "$0")
    case "$prog_name" in
        ${VCONTAINER_RUNTIME_NAME}-aarch64) echo "aarch64" ;;
        ${VCONTAINER_RUNTIME_NAME}-x86_64)  echo "x86_64" ;;
        *)                                   echo "" ;;
    esac
}

detect_default_arch() {
    # Check executable name first
    local name_arch=$(detect_arch_from_name)
    if [ -n "$name_arch" ]; then
        echo "$name_arch"
        return
    fi

    # Check environment variable
    local env_arch=$(_get_env_var ARCH)
    if [ -n "$env_arch" ]; then
        echo "$env_arch"
        return
    fi

    # Check new config file (arch key)
    local config_arch=$(config_get "arch" "")
    if [ -n "$config_arch" ]; then
        echo "$config_arch"
        return
    fi

    # Check legacy config file for backwards compatibility
    local legacy_file="$CONFIG_DIR/arch"
    if [ -f "$legacy_file" ]; then
        local legacy_arch=$(cat "$legacy_file" | tr -d '[:space:]')
        if [ -n "$legacy_arch" ]; then
            echo "$legacy_arch"
            return
        fi
    fi

    # Fall back to host architecture
    uname -m
}

DEFAULT_ARCH=$(detect_default_arch)
BLOB_DIR="$(_get_env_var BLOB_DIR)"
VERBOSE="$(_get_env_var VERBOSE)"
[ -z "$VERBOSE" ] && VERBOSE="false"
STATELESS="$(_get_env_var STATELESS)"
[ -z "$STATELESS" ] && STATELESS="false"

# Default state directory (per-architecture)
DEFAULT_STATE_DIR="$(_get_env_var STATE_DIR)"
[ -z "$DEFAULT_STATE_DIR" ] && DEFAULT_STATE_DIR="$HOME/.$VCONTAINER_RUNTIME_NAME"

# Other tool's state directory (for orphan checking)
OTHER_STATE_DIR="$HOME/.$(echo $VCONTAINER_OTHER_PREFIX | tr 'A-Z' 'a-z')"

# Runner script
RUNNER="$(_get_env_var RUNNER)"
[ -z "$RUNNER" ] && RUNNER="$SCRIPT_DIR/vrunner.sh"

# Colors (use $'...' for proper escape interpretation)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# Check OCI image architecture and warn/error if mismatched
# Usage: check_oci_arch <oci_dir> <target_arch>
# Returns: 0 if match or non-OCI, 1 if mismatch
check_oci_arch() {
    local oci_dir="$1"
    local target_arch="$2"

    # Only check OCI directories
    if [ ! -f "$oci_dir/index.json" ]; then
        return 0
    fi

    # Try to extract architecture from the OCI image
    # OCI structure: index.json -> manifest -> config blob -> architecture
    local image_arch=""

    # First, get the manifest digest from index.json
    local manifest_digest=$(cat "$oci_dir/index.json" 2>/dev/null | \
        grep -o '"digest"[[:space:]]*:[[:space:]]*"sha256:[a-f0-9]*"' | head -1 | \
        sed 's/.*sha256:\([a-f0-9]*\)".*/\1/')

    if [ -n "$manifest_digest" ]; then
        local manifest_file="$oci_dir/blobs/sha256/$manifest_digest"
        if [ -f "$manifest_file" ]; then
            # Get the config digest from manifest
            local config_digest=$(cat "$manifest_file" 2>/dev/null | \
                grep -o '"config"[[:space:]]*:[[:space:]]*{[^}]*"digest"[[:space:]]*:[[:space:]]*"sha256:[a-f0-9]*"' | \
                sed 's/.*sha256:\([a-f0-9]*\)".*/\1/')

            if [ -n "$config_digest" ]; then
                local config_file="$oci_dir/blobs/sha256/$config_digest"
                if [ -f "$config_file" ]; then
                    # Extract architecture from config
                    image_arch=$(cat "$config_file" 2>/dev/null | \
                        grep -o '"architecture"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | \
                        sed 's/.*"\([^"]*\)"$/\1/')
                fi
            fi
        fi
    fi

    if [ -z "$image_arch" ]; then
        # Couldn't determine architecture, allow import with warning
        echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Warning: Could not determine image architecture" >&2
        return 0
    fi

    # Normalize architecture names
    local normalized_image_arch="$image_arch"
    local normalized_target_arch="$target_arch"

    case "$image_arch" in
        arm64) normalized_image_arch="aarch64" ;;
        amd64) normalized_image_arch="x86_64" ;;
    esac

    case "$target_arch" in
        arm64) normalized_target_arch="aarch64" ;;
        amd64) normalized_target_arch="x86_64" ;;
    esac

    if [ "$normalized_image_arch" != "$normalized_target_arch" ]; then
        echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Architecture mismatch!" >&2
        echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC}   Image architecture: ${BOLD}$image_arch${NC}" >&2
        echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC}   Target architecture: ${BOLD}$target_arch${NC}" >&2
        echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Use --arch $image_arch to import to a matching environment" >&2
        return 1
    fi

    [ "$VERBOSE" = "true" ] && echo -e "${GREEN}[$VCONTAINER_RUNTIME_NAME]${NC} Image architecture: $image_arch (matches target)" >&2
    return 0
}

# ============================================================================
# Multi-Architecture OCI Support
# ============================================================================
# OCI Image Index (manifest list) format allows multiple platform-specific
# images under a single tag. These functions detect and handle multi-arch OCI.
# ============================================================================

# Normalize architecture name to OCI convention
# Usage: normalize_arch_to_oci <arch>
# Returns: OCI-format architecture (arm64, amd64, etc.)
normalize_arch_to_oci() {
    local arch="$1"
    case "$arch" in
        aarch64) echo "arm64" ;;
        x86_64)  echo "amd64" ;;
        *)       echo "$arch" ;;
    esac
}

# Normalize OCI architecture to Yocto/Linux convention
# Usage: normalize_arch_from_oci <arch>
# Returns: Linux-format architecture (aarch64, x86_64, etc.)
normalize_arch_from_oci() {
    local arch="$1"
    case "$arch" in
        arm64) echo "aarch64" ;;
        amd64) echo "x86_64" ;;
        *)     echo "$arch" ;;
    esac
}

# Resolve the file containing platform manifests in an OCI directory.
# Handles two layouts:
#   Flat:   index.json directly contains manifests with platform info
#   Nested: index.json → single image index blob → platform manifests
#           (skopeo-compatible format)
# Usage: _resolve_oci_platform_file <oci_dir>
# Prints: path to the file containing platform manifests, or empty
_resolve_oci_platform_file() {
    local oci_dir="$1"

    [ -f "$oci_dir/index.json" ] || return 1

    # Flat layout: platform info directly in index.json
    if grep -q '"platform"' "$oci_dir/index.json" 2>/dev/null; then
        echo "$oci_dir/index.json"
        return 0
    fi

    # Nested layout: index.json has a single entry with image.index mediaType
    if grep -q 'image\.index' "$oci_dir/index.json" 2>/dev/null; then
        local index_digest=$(grep -o '"sha256:[a-f0-9]*"' "$oci_dir/index.json" 2>/dev/null | head -1 | tr -d '"' | sed 's/sha256://')
        if [ -n "$index_digest" ] && [ -f "$oci_dir/blobs/sha256/$index_digest" ]; then
            if grep -q '"platform"' "$oci_dir/blobs/sha256/$index_digest" 2>/dev/null; then
                echo "$oci_dir/blobs/sha256/$index_digest"
                return 0
            fi
        fi
    fi

    return 1
}

# Check if OCI directory contains a multi-architecture Image Index
# Usage: is_oci_image_index <oci_dir>
# Returns: 0 if multi-arch, 1 if single-arch or not OCI
is_oci_image_index() {
    _resolve_oci_platform_file "$1" >/dev/null 2>&1
}

# Get list of available platforms in a multi-arch OCI Image Index
# Usage: get_oci_platforms <oci_dir>
# Returns: Space-separated list of architectures (e.g., "arm64 amd64")
get_oci_platforms() {
    local oci_dir="$1"
    local platform_file
    platform_file=$(_resolve_oci_platform_file "$oci_dir") || return 1

    grep -o '"architecture"[[:space:]]*:[[:space:]]*"[^"]*"' "$platform_file" 2>/dev/null | \
        sed 's/.*"\([^"]*\)"$/\1/' | \
        tr '\n' ' ' | sed 's/ $//'
}

# Select manifest digest for a specific platform from OCI Image Index
# Usage: select_platform_manifest <oci_dir> <target_arch>
# Returns: sha256 digest of the matching manifest (without "sha256:" prefix)
# Sets OCI_SELECTED_PLATFORM to the matched platform for informational purposes
select_platform_manifest() {
    local oci_dir="$1"
    local target_arch="$2"

    # Normalize target arch to OCI convention
    local oci_arch=$(normalize_arch_to_oci "$target_arch")

    # Resolve the file containing platform manifests (flat or nested)
    local manifest_index
    manifest_index=$(_resolve_oci_platform_file "$oci_dir") || return 1

    # Parse the manifest index to find manifest with matching platform
    # This is done without jq using grep/sed for portability
    local in_manifest=0
    local current_digest=""
    local current_arch=""
    local matched_digest=""

    while IFS= read -r line; do
        if echo "$line" | grep -q '"manifests"'; then
            in_manifest=1
            continue
        fi

        if [ "$in_manifest" = "1" ]; then
            if echo "$line" | grep -q '"digest"'; then
                current_digest=$(echo "$line" | sed 's/.*"sha256:\([a-f0-9]*\)".*/\1/')
            fi

            if echo "$line" | grep -q '"architecture"'; then
                current_arch=$(echo "$line" | sed 's/.*"architecture"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

                if [ "$current_arch" = "$oci_arch" ]; then
                    matched_digest="$current_digest"
                    OCI_SELECTED_PLATFORM="$current_arch"
                    break
                fi
            fi

            if echo "$line" | grep -q '^[[:space:]]*}'; then
                current_digest=""
                current_arch=""
            fi
        fi
    done < "$manifest_index"

    if [ -n "$matched_digest" ]; then
        echo "$matched_digest"
        return 0
    fi

    return 1
}

# Extract a single platform from multi-arch OCI to a new OCI directory
# Usage: extract_platform_oci <src_oci_dir> <dest_oci_dir> <manifest_digest>
# This creates a single-arch OCI directory that skopeo can import
extract_platform_oci() {
    local src_dir="$1"
    local dest_dir="$2"
    local manifest_digest="$3"

    mkdir -p "$dest_dir/blobs/sha256"

    # Copy the manifest blob
    cp "$src_dir/blobs/sha256/$manifest_digest" "$dest_dir/blobs/sha256/"

    # Read the manifest to get config and layer digests
    local manifest_file="$src_dir/blobs/sha256/$manifest_digest"

    # Extract and copy config blob
    local config_digest=$(grep -o '"config"[[:space:]]*:[[:space:]]*{[^}]*"digest"[[:space:]]*:[[:space:]]*"sha256:[a-f0-9]*"' "$manifest_file" | \
        sed 's/.*sha256:\([a-f0-9]*\)".*/\1/')
    if [ -n "$config_digest" ] && [ -f "$src_dir/blobs/sha256/$config_digest" ]; then
        cp "$src_dir/blobs/sha256/$config_digest" "$dest_dir/blobs/sha256/"
    fi

    # Extract and copy layer blobs
    grep -o '"digest"[[:space:]]*:[[:space:]]*"sha256:[a-f0-9]*"' "$manifest_file" | \
        sed 's/.*sha256:\([a-f0-9]*\)".*/\1/' | while read -r layer_digest; do
        if [ -f "$src_dir/blobs/sha256/$layer_digest" ]; then
            cp "$src_dir/blobs/sha256/$layer_digest" "$dest_dir/blobs/sha256/"
        fi
    done

    # Get manifest size
    local manifest_size=$(stat -c%s "$manifest_file" 2>/dev/null || stat -f%z "$manifest_file" 2>/dev/null)

    # Create new index.json pointing to just this manifest
    cat > "$dest_dir/index.json" << EOF
{
  "schemaVersion": 2,
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:$manifest_digest",
      "size": $manifest_size
    }
  ]
}
EOF

    # Copy oci-layout
    if [ -f "$src_dir/oci-layout" ]; then
        cp "$src_dir/oci-layout" "$dest_dir/"
    else
        echo '{"imageLayoutVersion": "1.0.0"}' > "$dest_dir/oci-layout"
    fi

    return 0
}

# ============================================================================
# Host-side OCI Image Cache (Xen standalone path)
# ============================================================================
# Cache layout:
#   ~/.vxn/images/refs/     - Symlinks from normalized image names to store dirs
#   ~/.vxn/images/store/    - Content-addressed OCI layout dirs by manifest digest

VXN_IMAGE_CACHE="${VXN_IMAGE_CACHE:-$HOME/.vxn/images}"

vxn_normalize_image_name() {
    # alpine → docker.io/library/alpine:latest
    # nginx:1.25 → docker.io/library/nginx:1.25
    # ghcr.io/foo/bar → ghcr.io/foo/bar:latest
    local name="$1"
    # Add default registry
    case "$name" in
        *.*/*) ;;                             # has registry (contains . before /)
        */*) name="docker.io/$name" ;;        # has namespace, no registry
        *)   name="docker.io/library/$name" ;; # bare name
    esac
    # Add default tag
    case "$name" in
        *:*) ;;                               # already has tag/digest
        *)   name="$name:latest" ;;
    esac
    echo "$name"
}

vxn_image_ref_key() {
    # docker.io/library/alpine:latest → docker.io_library_alpine:latest
    local name="$1"
    echo "$name" | tr '/' '_'
}

vxn_image_cache_lookup() {
    # Returns OCI dir path if cached, empty if not
    local image="$1"
    local normalized ref_key ref_link
    normalized=$(vxn_normalize_image_name "$image")
    ref_key=$(vxn_image_ref_key "$normalized")
    ref_link="$VXN_IMAGE_CACHE/refs/$ref_key"
    if [ -L "$ref_link" ] && [ -d "$ref_link" ]; then
        readlink -f "$ref_link"
    fi
}

vxn_image_cache_store() {
    # Store OCI dir in cache, create ref symlink
    # $1 = image name, $2 = source OCI dir
    local image="$1" oci_dir="$2"
    local normalized ref_key manifest_digest store_dir
    normalized=$(vxn_normalize_image_name "$image")
    ref_key=$(vxn_image_ref_key "$normalized")

    mkdir -p "$VXN_IMAGE_CACHE/refs" "$VXN_IMAGE_CACHE/store/sha256"

    # Get manifest digest for content-addressed storage
    manifest_digest=$(grep -o '"sha256:[a-f0-9]*"' "$oci_dir/index.json" 2>/dev/null | head -1 | tr -d '"')
    manifest_digest="${manifest_digest#sha256:}"
    if [ -z "$manifest_digest" ]; then
        # Fallback: hash the index.json itself
        manifest_digest=$(sha256sum "$oci_dir/index.json" | cut -d' ' -f1)
    fi

    store_dir="$VXN_IMAGE_CACHE/store/sha256/$manifest_digest"
    if [ ! -d "$store_dir" ]; then
        cp -a "$oci_dir" "$store_dir"
    fi

    # Create/update ref symlink (relative path)
    ln -sfn "../store/sha256/$manifest_digest" "$VXN_IMAGE_CACHE/refs/$ref_key"
}

vxn_image_cache_inspect() {
    # Print OCI config info (Entrypoint, Cmd, Env, WorkingDir)
    local oci_dir="$1"
    if ! command -v jq >/dev/null 2>&1; then
        echo "jq not found, cannot inspect image" >&2
        return 1
    fi
    local manifest_digest config_digest manifest_file config_file
    manifest_digest=$(jq -r '.manifests[0].digest' "$oci_dir/index.json" 2>/dev/null)
    manifest_file="$oci_dir/blobs/${manifest_digest/://}"
    [ -f "$manifest_file" ] || { echo "Manifest not found" >&2; return 1; }
    config_digest=$(jq -r '.config.digest' "$manifest_file" 2>/dev/null)
    config_file="$oci_dir/blobs/${config_digest/://}"
    [ -f "$config_file" ] || { echo "Config not found" >&2; return 1; }
    jq '{
        Entrypoint: .config.Entrypoint,
        Cmd: .config.Cmd,
        Env: .config.Env,
        WorkingDir: .config.WorkingDir,
        ExposedPorts: .config.ExposedPorts,
        Labels: .config.Labels,
        Architecture: .architecture,
        Os: .os
    }' "$config_file"
}

show_usage() {
    local PROG_NAME=$(basename "$0")
    local RUNTIME_UPPER=$(echo "$VCONTAINER_RUNTIME_CMD" | sed 's/./\U&/')
    cat << EOF
${BOLD}${PROG_NAME}${NC} v$VCONTAINER_VERSION - ${RUNTIME_UPPER} CLI for cross-architecture emulation

${BOLD}USAGE:${NC}
    ${PROG_NAME} [OPTIONS] <command> [args...]

${BOLD}${RUNTIME_UPPER}-COMPATIBLE COMMANDS:${NC}
  ${BOLD}Images:${NC}
    ${CYAN}images${NC}                       List images in emulated ${RUNTIME_UPPER}
    ${CYAN}pull${NC} <image>                 Pull image from registry
    ${CYAN}load${NC} -i <file>               Load ${RUNTIME_UPPER} image archive (${VCONTAINER_RUNTIME_CMD} save output)
    ${CYAN}import${NC} <tarball> [name:tag]  Import rootfs tarball as image
    ${CYAN}save${NC} -o <file> <image>       Save image to tar archive
    ${CYAN}tag${NC} <source> <target>        Tag an image
    ${CYAN}rmi${NC} <image>                  Remove an image
    ${CYAN}history${NC} <image>              Show image layer history
    ${CYAN}inspect${NC} <image|container>    Display detailed info

  ${BOLD}Containers:${NC}
    ${CYAN}run${NC} [opts] <image> [cmd]     Run a command in a new container
    ${CYAN}ps${NC} [options]                 List containers
    ${CYAN}rm${NC} <container>               Remove a container
    ${CYAN}logs${NC} <container>             View container logs
    ${CYAN}start${NC} <container>            Start a stopped container
    ${CYAN}stop${NC} <container>             Stop a running container
    ${CYAN}restart${NC} <container>          Restart a container
    ${CYAN}kill${NC} <container>             Kill a running container
    ${CYAN}pause${NC} <container>            Pause a running container
    ${CYAN}unpause${NC} <container>          Unpause a container
    ${CYAN}commit${NC} <container> <image>   Create image from container
    ${CYAN}exec${NC} [opts] <container> <cmd>  Execute command in container
    ${CYAN}vshell${NC}                       Open interactive shell in VM (debug)
    ${CYAN}cp${NC} <src> <dest>              Copy files to/from container

  ${BOLD}Registry:${NC}
    ${CYAN}login${NC} [options]              Log in to a registry
    ${CYAN}logout${NC} [registry]            Log out from a registry
    ${CYAN}push${NC} <image>                 Push image to registry
    ${CYAN}search${NC} <term>                Search registries for images

  ${BOLD}System:${NC}
    ${CYAN}info${NC}                         Display system info
    ${CYAN}version${NC}                      Show ${RUNTIME_UPPER} version
    ${CYAN}system df${NC}                    Show disk usage of images/containers/volumes
    ${CYAN}system prune${NC}                 Remove unused data
    ${CYAN}system prune -a${NC}              Remove all unused images

${BOLD}EXTENDED COMMANDS (${VCONTAINER_RUNTIME_NAME}-specific):${NC}
    ${CYAN}vimport${NC} <path> [name:tag]    Import from OCI dir, tarball, or directory (auto-detect)
                                 Multi-arch OCI Image Index supported (auto-selects platform)
    ${CYAN}bundle${NC} <image> <dir> [-- cmd]  Create OCI bundle from image (for vxn-oci-runtime)
    ${CYAN}vrun${NC} [opts] <image> [cmd]    Run command, clearing entrypoint (see RUN vs VRUN below)
    ${CYAN}vstorage${NC}                     List all storage directories (alias: vstorage list)
    ${CYAN}vstorage list${NC}                List all storage directories with details
    ${CYAN}vstorage path [arch]${NC}         Show path to storage directory
    ${CYAN}vstorage df${NC}                  Show detailed disk usage breakdown
    ${CYAN}vstorage clean [arch|--all]${NC}  Clean storage directories (stops memres first)
    ${CYAN}clean${NC}                        ${YELLOW}[DEPRECATED]${NC} Use 'vstorage clean' instead

${BOLD}MEMORY RESIDENT MODE (vmemres):${NC}
    By default, vmemres auto-starts on the first command and stops after idle timeout.
    This provides fast command execution without manual daemon management.

    ${CYAN}vmemres start${NC}                Start memory resident VM in background
    ${CYAN}vmemres stop${NC}                 Stop memory resident VM
    ${CYAN}vmemres restart${NC} [--clean]    Restart VM (optionally clean state first)
    ${CYAN}vmemres status${NC}               Show memory resident VM status
    ${CYAN}vmemres list${NC}                 List all running memres instances
    (Note: 'memres' also works as an alias for 'vmemres')

    Auto-start and idle timeout:
      - Daemon auto-starts when you run any command (configurable via vconfig auto-daemon)
      - Daemon auto-stops after 30 minutes of inactivity (configurable via vconfig idle-timeout)
      - Use --no-daemon to run commands in ephemeral mode (no daemon)

    ${BOLD}Dynamic Port Forwarding:${NC}
      When running detached containers with -p, port forwards are added dynamically:
        ${PROG_NAME} run -d -p 8080:80 nginx        # Adds 8080->80 forward
        ${PROG_NAME} run -d -p 3000:3000 myapp      # Adds 3000->3000 forward
        ${PROG_NAME} ps                              # Shows containers AND port forwards
        ${PROG_NAME} stop nginx                      # Removes 8080->80 forward

      Port format: -p <host_port>:<container_port>[/protocol]
        - protocol: tcp (default) or udp
        - Multiple -p options can be specified

    ${YELLOW}NOTE:${NC} Docker bridge networking (docker0) is used by default.
    Each container gets its own IP on 172.17.0.0/16. Port forwarding works via:
      Host:8080 -> QEMU -> VM:8080 -> Docker iptables -> Container:80
    Use --network=host for legacy behavior where containers share VM's network.
    Use --network=none to disable networking entirely.

${BOLD}RUN vs VRUN:${NC}
    ${CYAN}run${NC}   - Full ${RUNTIME_UPPER} passthrough. Entrypoint is honored.
            Command args are passed TO the entrypoint.
            Example: run alpine /bin/sh    -> entrypoint receives '/bin/sh' as arg
    ${CYAN}vrun${NC}  - Convenience wrapper. Clears entrypoint when command given.
            Command args become the container's command directly.
            Example: vrun alpine /bin/sh   -> runs /bin/sh as PID 1

    Use 'run' when you need --entrypoint, -e, --rm, or other ${VCONTAINER_RUNTIME_CMD} options.
    Use 'vrun' for simple "run this command in image" cases.

${BOLD}CONFIGURATION (vconfig):${NC}
    ${CYAN}vconfig${NC}                      Show all configuration values
    ${CYAN}vconfig${NC} <key>                Get configuration value
    ${CYAN}vconfig${NC} <key> <value>        Set configuration value
    ${CYAN}vconfig${NC} <key> --reset        Reset to default value

    Supported keys: arch, timeout, state-dir, verbose, idle-timeout, auto-daemon, registry
    Config file: \$CONFIG_DIR/config (default: ~/.config/${VCONTAINER_RUNTIME_NAME}/config)

    idle-timeout: Daemon idle timeout in seconds [default: 1800]
    auto-daemon:  Auto-start daemon on first command [default: true]
    registry:     Default registry for unqualified images (e.g., 10.0.2.2:5000/yocto)

${BOLD}GLOBAL OPTIONS:${NC}
    --arch, -a <arch>     Target architecture: x86_64 or aarch64 [default: ${DEFAULT_ARCH}]
    --config-dir <path>   Configuration directory [default: ~/.config/${VCONTAINER_RUNTIME_NAME}]
    --instance, -I <name> Use named instance (shortcut for --state-dir ~/.$VCONTAINER_RUNTIME_NAME/<name>)
    --blob-dir <path>     Path to kernel/initramfs blobs (override default)
    --stateless           Start with fresh ${RUNTIME_UPPER} state (no persistence)
    --state-dir <path>    Override state directory [default: ~/.$VCONTAINER_RUNTIME_NAME/<arch>]
    --storage <file>      Export ${VCONTAINER_RUNTIME_CMD} storage after command (tar file)
    --input-storage <tar> Load ${RUNTIME_UPPER} state from tar before command
    --no-kvm              Disable KVM acceleration (use TCG emulation)
    --no-daemon           Run in ephemeral mode (don't auto-start/use daemon)
    --registry <url>      Default registry for unqualified images (e.g., 10.0.2.2:5000/yocto)
    --no-registry         Disable baked-in default registry (use images as-is)
    --insecure-registry <host:port>  Mark registry as insecure (HTTP). Can repeat.
    --config <path>       Registry auth file (docker config.json / podman auth.json)
                          Defaults to \$VDKR_CONFIG / \$VPDMN_CONFIG. The file must be
                          mode 0600 or stricter; it is passed to the guest over a
                          dedicated read-only virtio-9p share and never appears on
                          the kernel cmdline.
    --verbose, -v         Enable verbose output
    --help, -h            Show this help

${BOLD}${RUNTIME_UPPER} RUN/VRUN OPTIONS:${NC}
    All ${VCONTAINER_RUNTIME_CMD} run options are passed through (e.g., -it, -e, -p, --rm, etc.)
    Interactive mode (-it) automatically handles daemon stop/restart
    -v <host>:<container>[:mode]  Mount host path in container (requires vmemres)
                                   mode: ro (read-only) or rw (read-write, default)

${BOLD}EXAMPLES:${NC}
    # List images (uses persistent state by default)
    ${PROG_NAME} images

    # Import rootfs tarball (matches '${VCONTAINER_RUNTIME_CMD} import' exactly)
    ${PROG_NAME} import rootfs.tar myapp:latest

    # Import OCI directory (extended command, auto-detects format)
    ${PROG_NAME} vimport ./container-oci/ myapp:latest
    ${PROG_NAME} images        # Image persists!

    # Save image to tar archive
    ${PROG_NAME} save -o myapp.tar myapp:latest

    # Load a ${RUNTIME_UPPER} image archive (from '${VCONTAINER_RUNTIME_CMD} save')
    ${PROG_NAME} load -i myapp.tar

    # Start fresh (ignore existing state)
    ${PROG_NAME} --stateless images

    # Export storage for deployment to target
    ${PROG_NAME} --storage /tmp/${VCONTAINER_RUNTIME_CMD}-storage.tar vimport ./container-oci/ myapp:latest

    # Run a command in a container (${VCONTAINER_RUNTIME_CMD}-compatible syntax)
    ${PROG_NAME} run alpine /bin/echo hello
    ${PROG_NAME} run --rm alpine uname -m      # Check container architecture

    # Interactive shell (${VCONTAINER_RUNTIME_CMD}-compatible syntax)
    ${PROG_NAME} run -it alpine /bin/sh

    # With environment variables and other ${VCONTAINER_RUNTIME_CMD} options
    ${PROG_NAME} run --rm -e FOO=bar myapp:latest
    ${PROG_NAME} run -it -p 8080:80 nginx:latest

    # Pull an image from a registry
    ${PROG_NAME} pull alpine:latest

    # Pull from local registry (configure once, use everywhere)
    ${PROG_NAME} vconfig registry 10.0.2.2:5000/yocto    # Set default registry
    ${PROG_NAME} pull container-base                     # Pulls from 10.0.2.2:5000/yocto/container-base

    # Or use --registry for one-off pulls
    ${PROG_NAME} --registry 10.0.2.2:5000/yocto pull container-base

    # vrun: convenience wrapper (clears entrypoint when command given)
    ${PROG_NAME} vrun myapp:latest /bin/ls -la  # Runs /bin/ls directly, not via entrypoint

    # Volume mounts (requires memres to be running)
    ${PROG_NAME} memres start
    ${PROG_NAME} vrun -v /tmp/data:/data alpine cat /data/file.txt
    ${PROG_NAME} vrun -v /home/user/src:/src:ro alpine ls /src
    ${PROG_NAME} run -v ./local:/app --rm myapp:latest /app/run.sh

    # Port forwarding (web server)
    ${PROG_NAME} memres start -p 8080:80           # Forward host:8080 to guest:80
    ${PROG_NAME} run -d --rm nginx:alpine          # Run nginx (--network=host is default)
    curl http://localhost:8080                     # Access nginx from host

    # Port forwarding (SSH into a container)
    ${PROG_NAME} memres start -p 2222:22           # Forward host:2222 to guest:22
    ${PROG_NAME} run -d my-ssh-image               # Container with SSH server
    ssh -p 2222 localhost                          # SSH from host into container

    # Multiple instances with different ports
    ${PROG_NAME} memres list                       # Show running instances
    ${PROG_NAME} -I web memres start -p 8080:80    # Start named instance
    ${PROG_NAME} -I web images                     # Use named instance
    ${PROG_NAME} -I backend run -d my-api:latest

${BOLD}NOTES:${NC}
    - Architecture detection (in priority order):
        1. --arch / -a flag
        2. Executable name (${VCONTAINER_RUNTIME_NAME}-aarch64 or ${VCONTAINER_RUNTIME_NAME}-x86_64)
        3. ${VCONTAINER_RUNTIME_PREFIX}_ARCH environment variable
        4. Config file: ~/.config/${VCONTAINER_RUNTIME_NAME}/arch
        5. Host architecture (uname -m)
    - Current architecture: ${DEFAULT_ARCH}
    - State persists in ~/.$VCONTAINER_RUNTIME_NAME/<arch>/
    - Use --stateless for fresh ${RUNTIME_UPPER} state each run
    - Use --storage to export ${RUNTIME_UPPER} storage to tar file
    - run vs vrun:
        run  = exact ${VCONTAINER_RUNTIME_CMD} run syntax (entrypoint honored)
        vrun = clears entrypoint when command given (runs command directly)

${BOLD}ENVIRONMENT:${NC}
    ${VCONTAINER_RUNTIME_PREFIX}_BLOB_DIR   Path to kernel/initramfs blobs
    ${VCONTAINER_RUNTIME_PREFIX}_STATE_DIR  Base directory for state [default: ~/.$VCONTAINER_RUNTIME_NAME]
    ${VCONTAINER_RUNTIME_PREFIX}_STATELESS  Run stateless by default (true/false)
    ${VCONTAINER_RUNTIME_PREFIX}_VERBOSE    Enable verbose output (true/false)

EOF
}

# Build runner args
build_runner_args() {
    local args=()

    # Specify runtime (docker for vdkr, podman for vpdmn)
    args+=("--runtime" "$VCONTAINER_RUNTIME_CMD")
    args+=("--arch" "$TARGET_ARCH")

    [ -n "$BLOB_DIR" ] && args+=("--blob-dir" "$BLOB_DIR")
    [ "$VERBOSE" = "true" ] && args+=("--verbose")
    [ "$NETWORK" = "true" ] && args+=("--network")
    [ "$INTERACTIVE" = "true" ] && args+=("--interactive")
    [ -n "$STORAGE_OUTPUT" ] && args+=("--output-type" "storage" "--output" "$STORAGE_OUTPUT")
    [ -n "$STATE_DIR" ] && args+=("--state-dir" "$STATE_DIR")
    [ -n "$INPUT_STORAGE" ] && args+=("--input-storage" "$INPUT_STORAGE")
    [ "$DISABLE_KVM" = "true" ] && args+=("--no-kvm")

    # Add idle timeout from config
    local idle_timeout=$(config_get "idle-timeout" "1800")
    args+=("--idle-timeout" "$idle_timeout")

    # Add port forwards (each -p adds a --port-forward)
    for pf in "${PORT_FORWARDS[@]}"; do
        args+=("--port-forward" "$pf")
    done

    # Add registry configuration
    [ -n "$REGISTRY" ] && args+=("--registry" "$REGISTRY")
    for reg in "${INSECURE_REGISTRIES[@]}"; do
        args+=("--insecure-registry" "$reg")
    done

    # Add secure registry options
    [ "$SECURE_REGISTRY" = "true" ] && args+=("--secure-registry")
    [ -n "$CA_CERT" ] && args+=("--ca-cert" "$CA_CERT")
    [ -n "$REGISTRY_USER" ] && args+=("--registry-user" "$REGISTRY_USER")
    [ -n "$REGISTRY_PASS" ] && args+=("--registry-pass" "$REGISTRY_PASS")
    [ -n "$AUTH_CONFIG" ] && args+=("--config" "$AUTH_CONFIG")

    # Xen: pass exit grace period
    [ -n "${VXN_EXIT_GRACE_PERIOD:-}" ] && args+=("--exit-grace-period" "$VXN_EXIT_GRACE_PERIOD")

    echo "${args[@]}"
}

# Parse global options first
TARGET_ARCH="$DEFAULT_ARCH"
STORAGE_OUTPUT=""
STATE_DIR=""
INPUT_STORAGE=""
NETWORK="true"
INTERACTIVE="false"
PORT_FORWARDS=()
DISABLE_KVM="false"
NO_DAEMON="false"
REGISTRY=""
INSECURE_REGISTRIES=()
SECURE_REGISTRY="false"
CA_CERT=""
REGISTRY_USER=""
REGISTRY_PASS=""
# Registry auth config file. Env-var default depends on which CLI wrapper is
# in use (vdkr → $VDKR_CONFIG, vpdmn → $VPDMN_CONFIG), then falls back to the
# other for convenience when sharing a single host-side file. Overridden by
# the --config CLI flag below.
AUTH_CONFIG="${VDKR_CONFIG:-${VPDMN_CONFIG:-}}"
COMMAND=""
COMMAND_ARGS=()

# Auto-detect bundled CA certificate for secure registry
# If CA cert is bundled in the tarball, automatically enable secure mode
BUNDLED_CA_CERT="$SCRIPT_DIR/registry/ca.crt"
if [ -f "$BUNDLED_CA_CERT" ]; then
    SECURE_REGISTRY="true"
    CA_CERT="$BUNDLED_CA_CERT"
fi

while [ $# -gt 0 ]; do
    case $1 in
        --arch|-a)
            # Only parse as global option before command is set
            if [ -z "$COMMAND" ]; then
                TARGET_ARCH="$2"
                shift 2
            else
                COMMAND_ARGS+=("$1")
                shift
            fi
            ;;
        --blob-dir)
            BLOB_DIR="$2"
            shift 2
            ;;
        --storage)
            STORAGE_OUTPUT="$2"
            shift 2
            ;;
        --state-dir)
            STATE_DIR="$2"
            shift 2
            ;;
        --instance|-I)
            # Shortcut: -I web expands to --state-dir ~/.$VCONTAINER_RUNTIME_NAME/web
            STATE_DIR="$DEFAULT_STATE_DIR/$2"
            shift 2
            ;;
        --config-dir)
            # Already pre-parsed, just consume it
            shift 2
            ;;
        --config-dir=*)
            # Already pre-parsed, just consume it
            shift
            ;;
        --input-storage)
            INPUT_STORAGE="$2"
            shift 2
            ;;
        --stateless)
            STATELESS="true"
            shift
            ;;
        --no-network)
            NETWORK="false"
            shift
            ;;
        --no-kvm)
            DISABLE_KVM="true"
            shift
            ;;
        --no-daemon)
            NO_DAEMON="true"
            shift
            ;;
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --no-registry)
            # Explicitly disable baked-in registry (passes docker_registry=none to init)
            REGISTRY="none"
            shift
            ;;
        --insecure-registry)
            INSECURE_REGISTRIES+=("$2")
            shift 2
            ;;
        --secure-registry)
            SECURE_REGISTRY="true"
            shift
            ;;
        --ca-cert)
            CA_CERT="$2"
            shift 2
            ;;
        --registry-user)
            REGISTRY_USER="$2"
            shift 2
            ;;
        --registry-password|--registry-pass)
            REGISTRY_PASS="$2"
            shift 2
            ;;
        --config)
            # Path to a docker/podman registry auth file (config.json / auth.json).
            # Overrides $VDKR_CONFIG / $VPDMN_CONFIG. Forwarded to vrunner.sh --config,
            # which validates the file and stages it on a dedicated read-only 9p share.
            AUTH_CONFIG="$2"
            shift 2
            ;;
        -it|--interactive)
            INTERACTIVE="true"
            shift
            ;;
        -i)
            # -i alone means interactive, but only before we have a command
            # After a command, -i might be an argument (e.g., load -i file)
            if [ -z "$COMMAND" ]; then
                INTERACTIVE="true"
            else
                COMMAND_ARGS+=("$1")
            fi
            shift
            ;;
        -t)
            # -t alone means interactive (allocate TTY) before command
            # After command, -t might be an argument
            if [ -z "$COMMAND" ]; then
                INTERACTIVE="true"
            else
                COMMAND_ARGS+=("$1")
            fi
            shift
            ;;
        --verbose)
            VERBOSE="true"
            shift
            ;;
        -v)
            # -v can mean verbose (before command) or volume (after command like run/vrun)
            if [ -z "$COMMAND" ]; then
                VERBOSE="true"
            else
                # After command, -v is likely a volume flag - pass to subcommand
                COMMAND_ARGS+=("$1")
            fi
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        --version)
            echo "$VCONTAINER_RUNTIME_NAME version $VCONTAINER_VERSION"
            exit 0
            ;;
        -*)
            # Unknown option - might be for subcommand
            COMMAND_ARGS+=("$1")
            shift
            ;;
        *)
            if [ -z "$COMMAND" ]; then
                COMMAND="$1"
            else
                COMMAND_ARGS+=("$1")
            fi
            shift
            ;;
    esac
done

if [ -z "$COMMAND" ]; then
    show_usage
    exit 0
fi

# Set up state directory (default to persistent unless --stateless)
if [ "$STATELESS" != "true" ] && [ -z "$STATE_DIR" ] && [ -z "$INPUT_STORAGE" ]; then
    STATE_DIR="$DEFAULT_STATE_DIR/$TARGET_ARCH"
fi

# Read registry from config if not set via CLI
if [ -z "$REGISTRY" ]; then
    REGISTRY=$(config_get "registry" "")
fi

# Check runner exists
if [ ! -x "$RUNNER" ]; then
    echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Runner script not found: $RUNNER" >&2
    exit 1
fi

# Helper function to check if daemon is running
daemon_is_running() {
    # Use STATE_DIR if set, otherwise use default
    local state_dir="${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}"
    local pid_file="$state_dir/daemon.pid"
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if [ -d "/proc/$pid" ]; then
            return 0
        fi
    fi
    return 1
}

# ============================================================================
# QMP (QEMU Machine Protocol) Helpers for Dynamic Port Forwarding
# ============================================================================
# These functions communicate with QEMU's QMP socket to add/remove port
# forwards at runtime without restarting the daemon.

# Get the QMP socket path
get_qmp_socket() {
    local state_dir="${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}"
    echo "$state_dir/qmp.sock"
}

# Send a QMP command and get the response
# Usage: qmp_send "command-line"
qmp_send() {
    local cmd="$1"
    local qmp_socket=$(get_qmp_socket)

    if [ ! -S "$qmp_socket" ]; then
        echo "QMP socket not found: $qmp_socket" >&2
        return 1
    fi

    # QMP requires a capabilities negotiation first, then human-monitor-command
    # We use socat to send the command
    {
        echo '{"execute":"qmp_capabilities"}'
        sleep 0.1
        echo "{\"execute\":\"human-monitor-command\",\"arguments\":{\"command-line\":\"$cmd\"}}"
    } | socat - "unix-connect:$qmp_socket" 2>/dev/null
}

# Add a port forward to the running daemon
# Usage: qmp_add_hostfwd <host_port> <guest_port> [protocol]
# With bridge networking: QEMU forwards host:port -> VM:port, Docker handles VM:port -> container:port
qmp_add_hostfwd() {
    local host_port="$1"
    local guest_port="$2"
    local protocol="${3:-tcp}"

    [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Adding port forward: ${host_port} -> ${guest_port}/${protocol}" >&2

    # QEMU forwards to host_port on VM; Docker -p handles the container port mapping
    local result=$(qmp_send "hostfwd_add net0 ${protocol}::${host_port}-:${host_port}")
    if echo "$result" | grep -q '"error"'; then
        echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Failed to add port forward: $result" >&2
        return 1
    fi
    return 0
}

# Remove a port forward from the running daemon
# Usage: qmp_remove_hostfwd <host_port> [protocol]
qmp_remove_hostfwd() {
    local host_port="$1"
    local protocol="${2:-tcp}"

    [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Removing port forward: ${host_port}/${protocol}" >&2

    local result=$(qmp_send "hostfwd_remove net0 ${protocol}::${host_port}")
    if echo "$result" | grep -q '"error"'; then
        echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Failed to remove port forward: $result" >&2
        return 1
    fi
    return 0
}

# ============================================================================
# Port Forward Registry
# ============================================================================
# Track which ports are forwarded for which containers so we can clean up
# when containers are stopped.

PORT_FORWARD_FILE=""

get_port_forward_file() {
    if [ -z "$PORT_FORWARD_FILE" ]; then
        local state_dir="${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}"
        PORT_FORWARD_FILE="$state_dir/port-forwards.txt"
    fi
    echo "$PORT_FORWARD_FILE"
}

# Register a port forward for a container
# Usage: register_port_forward <container_name> <host_port> <guest_port> [protocol]
register_port_forward() {
    local container_name="$1"
    local host_port="$2"
    local guest_port="$3"
    local protocol="${4:-tcp}"

    local pf_file=$(get_port_forward_file)
    mkdir -p "$(dirname "$pf_file")"
    echo "${container_name}:${host_port}:${guest_port}:${protocol}" >> "$pf_file"
}

# Unregister and remove port forwards for a container
# Usage: unregister_port_forwards <container_name>
unregister_port_forwards() {
    local container_name="$1"
    local pf_file=$(get_port_forward_file)

    if [ ! -f "$pf_file" ]; then
        return 0
    fi

    # Find and remove all port forwards for this container
    local temp_file="${pf_file}.tmp"
    while IFS=: read -r name host_port guest_port protocol; do
        if [ "$name" = "$container_name" ]; then
            qmp_remove_hostfwd "$host_port" "$protocol"
        else
            echo "${name}:${host_port}:${guest_port}:${protocol}"
        fi
    done < "$pf_file" > "$temp_file"
    mv "$temp_file" "$pf_file"
}

# List all registered port forwards
# Usage: list_port_forwards [container_name]
list_port_forwards() {
    local filter_name="$1"
    local pf_file=$(get_port_forward_file)

    if [ ! -f "$pf_file" ]; then
        return 0
    fi

    while IFS=: read -r name host_port guest_port protocol; do
        if [ -z "$filter_name" ] || [ "$name" = "$filter_name" ]; then
            echo "0.0.0.0:${host_port}->${guest_port}/${protocol}"
        fi
    done < "$pf_file"
}

# Helper function to run command via daemon or regular mode
run_runtime_command() {
    local runtime_cmd="$1"
    local runner_args=$(build_runner_args)

    # Check for --no-daemon flag - use ephemeral mode
    if [ "$NO_DAEMON" = "true" ]; then
        [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Using ephemeral mode (--no-daemon)" >&2
        "$RUNNER" $runner_args -- "$runtime_cmd"
        return $?
    fi

    if daemon_is_running; then
        # Use daemon mode - faster
        [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Using daemon mode" >&2
        "$RUNNER" $runner_args --daemon-send "$runtime_cmd"
    else
        # Check if auto-daemon is enabled
        local auto_daemon=$(config_get "auto-daemon" "true")
        if [ "$auto_daemon" = "true" ]; then
            # Auto-start daemon (idle-timeout is included in runner_args)
            echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Starting daemon..." >&2
            "$RUNNER" $runner_args --daemon-start

            if daemon_is_running; then
                # Fresh daemon has no port forwards - clear stale registry
                local pf_file=$(get_port_forward_file)
                if [ -f "$pf_file" ]; then
                    [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Clearing stale port forward registry" >&2
                    rm -f "$pf_file"
                fi
                [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Using daemon mode" >&2
                "$RUNNER" $runner_args --daemon-send "$runtime_cmd"
            else
                echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Failed to start daemon, using ephemeral mode" >&2
                "$RUNNER" $runner_args -- "$runtime_cmd"
            fi
        else
            # Auto-daemon disabled - use ephemeral mode
            "$RUNNER" $runner_args -- "$runtime_cmd"
        fi
    fi
}

# Helper function to run command with input
# Uses daemon mode with virtio-9p if daemon is running, otherwise regular mode
run_runtime_command_with_input() {
    local input_path="$1"
    local input_type="$2"
    local runtime_cmd="$3"
    local runner_args=$(build_runner_args)

    # Check for --no-daemon flag - use ephemeral mode
    if [ "$NO_DAEMON" = "true" ]; then
        [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Using ephemeral mode (--no-daemon)" >&2
        "$RUNNER" $runner_args --input "$input_path" --input-type "$input_type" -- "$runtime_cmd"
        return $?
    fi

    if daemon_is_running; then
        # Use daemon mode with virtio-9p shared directory
        [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Using daemon mode for file I/O" >&2
        "$RUNNER" $runner_args --input "$input_path" --input-type "$input_type" --daemon-send-input -- "$runtime_cmd"
    else
        # Check if auto-daemon is enabled
        local auto_daemon=$(config_get "auto-daemon" "true")
        if [ "$auto_daemon" = "true" ]; then
            # Auto-start daemon (idle-timeout is included in runner_args)
            echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Starting daemon..." >&2
            "$RUNNER" $runner_args --daemon-start

            if daemon_is_running; then
                # Fresh daemon has no port forwards - clear stale registry
                local pf_file=$(get_port_forward_file)
                if [ -f "$pf_file" ]; then
                    [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Clearing stale port forward registry" >&2
                    rm -f "$pf_file"
                fi
                [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Using daemon mode for file I/O" >&2
                "$RUNNER" $runner_args --input "$input_path" --input-type "$input_type" --daemon-send-input -- "$runtime_cmd"
            else
                echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Failed to start daemon, using ephemeral mode" >&2
                "$RUNNER" $runner_args --input "$input_path" --input-type "$input_type" -- "$runtime_cmd"
            fi
        else
            # Auto-daemon disabled - use ephemeral mode
            "$RUNNER" $runner_args --input "$input_path" --input-type "$input_type" -- "$runtime_cmd"
        fi
    fi
}

# ============================================================================
# Volume Mount Support
# ============================================================================
# Volumes are copied to the share directory before running the container.
# Format: -v /host/path:/container/path[:ro|:rw]
#
# Implementation:
#   - Copy host path to $SHARE_DIR/volumes/<hash>/
#   - Transform -v to use /mnt/share/volumes/<hash>:/container/path
#   - After container exits, sync back for :rw mounts (default)
#
# Limitations:
#   - Requires daemon mode (memres) for volume mounts
#   - Changes in container are synced back after container exits (not real-time)
#   - Large volumes may be slow to copy
# ============================================================================

# Array to track volume mounts for cleanup/sync
declare -a VOLUME_MOUNTS=()
declare -a VOLUME_MODES=()

# Generate a short hash for volume directory naming
volume_hash() {
    echo "$1" | md5sum | cut -c1-8
}

# Global to receive result from prepare_volume (avoids subshell issue)
PREPARE_VOLUME_RESULT=""

# Prepare a volume mount: copy host path to share directory
# Sets PREPARE_VOLUME_RESULT to the guest path (avoids subshell issue with arrays)
prepare_volume() {
    local host_path="$1"
    local container_path="$2"
    local mode="$3"  # ro or rw (default: rw)

    [ -z "$mode" ] && mode="rw"
    PREPARE_VOLUME_RESULT=""

    # Validate host path exists
    if [ ! -e "$host_path" ]; then
        echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Volume source not found: $host_path" >&2
        return 1
    fi

    # Get share directory
    local share_dir="${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}/share"
    local volumes_dir="$share_dir/volumes"

    # Create volumes directory
    mkdir -p "$volumes_dir"

    # Generate unique directory name based on host path
    local hash=$(volume_hash "$host_path")
    local vol_dir="$volumes_dir/$hash"

    # Clean and copy
    rm -rf "$vol_dir"
    mkdir -p "$vol_dir"

    if [ -d "$host_path" ]; then
        # Directory: copy contents
        cp -rL "$host_path"/* "$vol_dir/" 2>/dev/null || true
        [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Volume: copied directory $host_path -> /mnt/share/volumes/$hash" >&2
    else
        # File: copy file
        cp -L "$host_path" "$vol_dir/"
        [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Volume: copied file $host_path -> /mnt/share/volumes/$hash" >&2
    fi

    # Sync to ensure data is visible to guest
    sync

    # Track for later sync-back (in parent shell, not subshell)
    VOLUME_MOUNTS+=("$host_path:$vol_dir:$container_path")
    VOLUME_MODES+=("$mode")

    # Set result in global variable (caller reads this, not $(prepare_volume))
    PREPARE_VOLUME_RESULT="/mnt/share/volumes/$hash"
}

# Sync volumes back from guest to host (for :rw mounts)
sync_volumes_back() {
    local share_dir="${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}/share"
    local volumes_dir="$share_dir/volumes"

    # Wait for 9p filesystem to sync writes from guest to host
    sleep 1
    sync

    for i in "${!VOLUME_MOUNTS[@]}"; do
        local mount="${VOLUME_MOUNTS[$i]}"
        local mode="${VOLUME_MODES[$i]}"

        if [ "$mode" = "rw" ]; then
            # Parse mount string: host_path:vol_dir:container_path
            local host_path=$(echo "$mount" | cut -d: -f1)
            local vol_dir=$(echo "$mount" | cut -d: -f2)

            if [ -d "$vol_dir" ] && [ -d "$host_path" ]; then
                [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Syncing volume back: $vol_dir -> $host_path" >&2
                # Use rsync if available, otherwise cp
                if command -v rsync >/dev/null 2>&1; then
                    rsync -a --delete "$vol_dir/" "$host_path/"
                else
                    rm -rf "$host_path"/*
                    cp -rL "$vol_dir"/* "$host_path/" 2>/dev/null || true
                fi
            elif [ -f "$host_path" ]; then
                # Single file mount
                local filename=$(basename "$host_path")
                if [ -f "$vol_dir/$filename" ]; then
                    cp -L "$vol_dir/$filename" "$host_path"
                fi
            fi
        fi
    done
}

# Clean up volume directories
cleanup_volumes() {
    local share_dir="${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}/share"
    local volumes_dir="$share_dir/volumes"

    if [ -d "$volumes_dir" ]; then
        rm -rf "$volumes_dir"
    fi

    # Clear tracking arrays
    VOLUME_MOUNTS=()
    VOLUME_MODES=()
}

# Global variable to hold transformed volume arguments
TRANSFORMED_VOLUME_ARGS=()

# Parse volume mounts from arguments and transform them
# Input: array elements passed as arguments
# Output: sets TRANSFORMED_VOLUME_ARGS with transformed arguments
# Side effect: populates VOLUME_MOUNTS array
parse_and_prepare_volumes() {
    TRANSFORMED_VOLUME_ARGS=()
    local args=("$@")
    local i=0

    while [ $i -lt ${#args[@]} ]; do
        local arg="${args[$i]}"

        case "$arg" in
            -v|--volume)
                # Next arg is the volume spec
                i=$((i + 1))
                if [ $i -ge ${#args[@]} ]; then
                    echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} -v requires an argument" >&2
                    return 1
                fi
                local vol_spec="${args[$i]}"

                # Parse volume spec: host:container[:mode]
                local host_path=$(echo "$vol_spec" | cut -d: -f1)
                local container_path=$(echo "$vol_spec" | cut -d: -f2)
                local mode=$(echo "$vol_spec" | cut -d: -f3)

                # Make host path absolute
                if [[ "$host_path" != /* ]]; then
                    host_path="$(pwd)/$host_path"
                fi

                # Prepare volume (sets PREPARE_VOLUME_RESULT global)
                prepare_volume "$host_path" "$container_path" "$mode" || return 1
                local guest_path="$PREPARE_VOLUME_RESULT"

                # Add transformed volume option
                if [ -d "$host_path" ]; then
                    TRANSFORMED_VOLUME_ARGS+=("-v" "${guest_path}:${container_path}${mode:+:$mode}")
                else
                    # For single file, include filename
                    local filename=$(basename "$host_path")
                    TRANSFORMED_VOLUME_ARGS+=("-v" "${guest_path}/${filename}:${container_path}${mode:+:$mode}")
                fi
                ;;
            *)
                TRANSFORMED_VOLUME_ARGS+=("$arg")
                ;;
        esac
        i=$((i + 1))
    done
}

# ============================================================================
# VXN Container State Helpers (Xen per-container DomU)
# ============================================================================

# VXN container state directory
vxn_container_dir() { echo "$HOME/.vxn/containers/$1"; }

vxn_container_is_running() {
    local cdir="$(vxn_container_dir "$1")"
    [ -f "$cdir/daemon.domname" ] || return 1
    local domname=$(cat "$cdir/daemon.domname")
    xl list "$domname" >/dev/null 2>&1
}

# Query entrypoint status from a running vxn container.
# Returns: "Running", "Exited (<code>)", or "Unknown"
vxn_container_status() {
    local name="$1"
    local cdir="$(vxn_container_dir "$name")"

    # DomU not alive at all
    if ! vxn_container_is_running "$name"; then
        echo "Exited"
        return
    fi

    # Query the guest via PTY for entrypoint status
    local pty_file="$cdir/daemon.pty"
    if [ -f "$pty_file" ]; then
        local pty
        pty=$(cat "$pty_file")
        if [ -c "$pty" ]; then
            # Open PTY, send STATUS query, read response
            local status_line=""
            exec 4<>"$pty"
            # Drain pending output
            while IFS= read -t 0.3 -r _discard <&4; do :; done
            echo "===STATUS===" >&4
            while IFS= read -t 3 -r status_line <&4; do
                status_line=$(echo "$status_line" | tr -d '\r')
                case "$status_line" in
                    *"===RUNNING==="*)
                        exec 4<&- 4>&- 2>/dev/null
                        echo "Running"
                        return
                        ;;
                    *"===EXITED="*"==="*)
                        local code=$(echo "$status_line" | sed 's/.*===EXITED=\([0-9]*\)===/\1/')
                        exec 4<&- 4>&- 2>/dev/null
                        echo "Exited ($code)"
                        return
                        ;;
                esac
            done
            exec 4<&- 4>&- 2>/dev/null
        fi
    fi

    # Could not determine — DomU is alive but status query failed
    echo "Running"
}

# Xen: error helper for unsupported commands
vxn_unsupported() {
    echo "${VCONTAINER_RUNTIME_NAME}: '$1' is not supported (VM is the container, no runtime inside)" >&2
    exit 1
}
vxn_not_yet() {
    echo "${VCONTAINER_RUNTIME_NAME}: '$1' is not yet supported" >&2
    exit 1
}

# Handle commands
case "$COMMAND" in
    image)
        # Handle "docker image *" compound commands
        # docker image ls → docker images
        # docker image rm → docker rmi
        # docker image pull → docker pull
        # etc.
        if [ ${#COMMAND_ARGS[@]} -lt 1 ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} image requires a subcommand (ls, rm, pull, inspect, tag, push, prune)" >&2
            exit 1
        fi
        SUBCMD="${COMMAND_ARGS[0]}"
        SUBCMD_ARGS=("${COMMAND_ARGS[@]:1}")
        if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ]; then
            # Xen: delegate to cache-based image subcommands
            case "$SUBCMD" in
                ls|list)
                    printf "%-40s %-15s %-12s\n" "REPOSITORY:TAG" "SIZE" "CACHED"
                    if [ -d "$VXN_IMAGE_CACHE/refs" ]; then
                        for ref in "$VXN_IMAGE_CACHE/refs"/*; do
                            [ -L "$ref" ] || continue
                            _vxn_ref_name=$(basename "$ref" | tr '_' '/')
                            _vxn_store_dir=$(readlink -f "$ref")
                            _vxn_size="unknown"
                            [ -d "$_vxn_store_dir" ] && _vxn_size=$(du -sh "$_vxn_store_dir" 2>/dev/null | cut -f1)
                            printf "%-40s %-15s %-12s\n" "$_vxn_ref_name" "$_vxn_size" "yes"
                        done
                    fi
                    exit 0
                    ;;
                rm|remove)
                    [ ${#SUBCMD_ARGS[@]} -lt 1 ] && { echo "rmi requires <image>" >&2; exit 1; }
                    _vxn_normalized=$(vxn_normalize_image_name "${SUBCMD_ARGS[0]}")
                    _vxn_ref_key=$(vxn_image_ref_key "$_vxn_normalized")
                    _vxn_ref_link="$VXN_IMAGE_CACHE/refs/$_vxn_ref_key"
                    if [ -L "$_vxn_ref_link" ]; then
                        _vxn_store_dir=$(readlink -f "$_vxn_ref_link")
                        rm -f "$_vxn_ref_link"
                        _vxn_other_refs=$(find "$VXN_IMAGE_CACHE/refs" -lname "*/$(basename "$_vxn_store_dir")" 2>/dev/null | wc -l)
                        [ "$_vxn_other_refs" -eq 0 ] && rm -rf "$_vxn_store_dir"
                        echo "Removed: $_vxn_normalized"
                    else
                        echo "Image not found: $_vxn_normalized" >&2; exit 1
                    fi
                    exit 0
                    ;;
                pull)
                    [ ${#SUBCMD_ARGS[@]} -lt 1 ] && { echo "pull requires <image>" >&2; exit 1; }
                    IMAGE_NAME="${SUBCMD_ARGS[0]}"
                    command -v skopeo >/dev/null 2>&1 || { echo "skopeo not found" >&2; exit 1; }
                    _vxn_normalized=$(vxn_normalize_image_name "$IMAGE_NAME")
                    echo "Pulling $_vxn_normalized..."
                    _vxn_tmpoci="$(mktemp -d)/oci-image"
                    if skopeo copy "docker://$_vxn_normalized" "oci:$_vxn_tmpoci:latest" 2>&1; then
                        vxn_image_cache_store "$IMAGE_NAME" "$_vxn_tmpoci"
                        rm -rf "$(dirname "$_vxn_tmpoci")"
                        echo "Pulled: $_vxn_normalized"
                    else
                        rm -rf "$(dirname "$_vxn_tmpoci")"
                        echo "Failed to pull $_vxn_normalized" >&2; exit 1
                    fi
                    exit 0
                    ;;
                inspect)
                    [ ${#SUBCMD_ARGS[@]} -lt 1 ] && { echo "inspect requires <image>" >&2; exit 1; }
                    _vxn_cached_oci=$(vxn_image_cache_lookup "${SUBCMD_ARGS[0]}")
                    if [ -n "$_vxn_cached_oci" ]; then
                        vxn_image_cache_inspect "$_vxn_cached_oci"
                    else
                        echo "Image not found: ${SUBCMD_ARGS[0]}" >&2; exit 1
                    fi
                    exit 0
                    ;;
                tag)
                    [ ${#SUBCMD_ARGS[@]} -lt 2 ] && { echo "tag requires <source> <target>" >&2; exit 1; }
                    _vxn_src_oci=$(vxn_image_cache_lookup "${SUBCMD_ARGS[0]}")
                    if [ -z "$_vxn_src_oci" ]; then
                        echo "Image not found: ${SUBCMD_ARGS[0]}" >&2; exit 1
                    fi
                    _vxn_target_normalized=$(vxn_normalize_image_name "${SUBCMD_ARGS[1]}")
                    _vxn_target_ref_key=$(vxn_image_ref_key "$_vxn_target_normalized")
                    mkdir -p "$VXN_IMAGE_CACHE/refs"
                    # Point new ref to same store dir
                    _vxn_store_base=$(basename "$_vxn_src_oci")
                    ln -sfn "../store/sha256/$_vxn_store_base" "$VXN_IMAGE_CACHE/refs/$_vxn_target_ref_key"
                    echo "Tagged: $_vxn_target_normalized"
                    exit 0
                    ;;
                push)
                    vxn_not_yet "image push"
                    ;;
                prune)
                    vxn_not_yet "image prune"
                    ;;
                history)
                    vxn_not_yet "image history"
                    ;;
                *)
                    echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Unknown image subcommand: $SUBCMD" >&2
                    exit 1
                    ;;
            esac
        fi
        case "$SUBCMD" in
            ls|list)
                run_runtime_command "$VCONTAINER_RUNTIME_CMD images ${SUBCMD_ARGS[*]}"
                ;;
            rm|remove)
                run_runtime_command "$VCONTAINER_RUNTIME_CMD rmi ${SUBCMD_ARGS[*]}"
                ;;
            pull)
                # Reuse pull logic - set COMMAND_ARGS and fall through
                COMMAND_ARGS=("${SUBCMD_ARGS[@]}")
                if [ ${#COMMAND_ARGS[@]} -lt 1 ]; then
                    echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} image pull requires <image>" >&2
                    exit 1
                fi
                IMAGE_NAME="${COMMAND_ARGS[0]}"
                if daemon_is_running; then
                    run_runtime_command "$VCONTAINER_RUNTIME_CMD pull $IMAGE_NAME && $VCONTAINER_RUNTIME_CMD images"
                else
                    NETWORK="true"
                    RUNNER_ARGS=$(build_runner_args)
                    "$RUNNER" $RUNNER_ARGS -- "$VCONTAINER_RUNTIME_CMD pull $IMAGE_NAME && $VCONTAINER_RUNTIME_CMD images"
                fi
                ;;
            inspect)
                run_runtime_command "$VCONTAINER_RUNTIME_CMD inspect ${SUBCMD_ARGS[*]}"
                ;;
            tag)
                run_runtime_command "$VCONTAINER_RUNTIME_CMD tag ${SUBCMD_ARGS[*]}"
                ;;
            push)
                NETWORK="true"
                run_runtime_command "$VCONTAINER_RUNTIME_CMD push ${SUBCMD_ARGS[*]}"
                ;;
            prune)
                run_runtime_command "$VCONTAINER_RUNTIME_CMD image prune ${SUBCMD_ARGS[*]}"
                ;;
            history)
                run_runtime_command "$VCONTAINER_RUNTIME_CMD history ${SUBCMD_ARGS[*]}"
                ;;
            *)
                echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Unknown image subcommand: $SUBCMD" >&2
                echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Valid subcommands: ls, rm, pull, inspect, tag, push, prune, history" >&2
                exit 1
                ;;
        esac
        ;;

    images)
        if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ]; then
            printf "%-40s %-15s %-12s\n" "REPOSITORY:TAG" "SIZE" "CACHED"
            if [ -d "$VXN_IMAGE_CACHE/refs" ]; then
                for ref in "$VXN_IMAGE_CACHE/refs"/*; do
                    [ -L "$ref" ] || continue
                    _vxn_ref_name=$(basename "$ref" | tr '_' '/')
                    _vxn_store_dir=$(readlink -f "$ref")
                    _vxn_size="unknown"
                    [ -d "$_vxn_store_dir" ] && _vxn_size=$(du -sh "$_vxn_store_dir" 2>/dev/null | cut -f1)
                    printf "%-40s %-15s %-12s\n" "$_vxn_ref_name" "$_vxn_size" "yes"
                done
            fi
            exit 0
        fi
        # runtime images
        run_runtime_command "$VCONTAINER_RUNTIME_CMD images ${COMMAND_ARGS[*]}"
        ;;

    pull)
        # runtime pull <image>
        if [ ${#COMMAND_ARGS[@]} -lt 1 ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} pull requires <image>" >&2
            exit 1
        fi

        IMAGE_NAME="${COMMAND_ARGS[0]}"

        if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ]; then
            # Host-side pull via skopeo → cache
            command -v skopeo >/dev/null 2>&1 || { echo "skopeo not found" >&2; exit 1; }
            _vxn_normalized=$(vxn_normalize_image_name "$IMAGE_NAME")
            echo "Pulling $_vxn_normalized..."
            _vxn_tmpoci="$(mktemp -d)/oci-image"
            if skopeo copy "docker://$_vxn_normalized" "oci:$_vxn_tmpoci:latest" 2>&1; then
                vxn_image_cache_store "$IMAGE_NAME" "$_vxn_tmpoci"
                rm -rf "$(dirname "$_vxn_tmpoci")"
                echo "Pulled: $_vxn_normalized"
            else
                rm -rf "$(dirname "$_vxn_tmpoci")"
                echo "Failed to pull $_vxn_normalized" >&2; exit 1
            fi
            exit 0
        fi

        # Daemon mode already has networking enabled, so this works via daemon
        if daemon_is_running; then
            # Use daemon mode (already has networking)
            run_runtime_command "$VCONTAINER_RUNTIME_CMD pull $IMAGE_NAME && $VCONTAINER_RUNTIME_CMD images"
        else
            # Regular mode - need to enable networking
            NETWORK="true"
            RUNNER_ARGS=$(build_runner_args)
            "$RUNNER" $RUNNER_ARGS -- "$VCONTAINER_RUNTIME_CMD pull $IMAGE_NAME && $VCONTAINER_RUNTIME_CMD images"
        fi
        ;;

    load)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "load"
        # runtime load -i <file>
        # Parse -i argument
        INPUT_FILE=""
        LOAD_ARGS=()
        i=0
        while [ $i -lt ${#COMMAND_ARGS[@]} ]; do
            arg="${COMMAND_ARGS[$i]}"
            case "$arg" in
                -i|--input)
                    i=$((i + 1))
                    INPUT_FILE="${COMMAND_ARGS[$i]}"
                    ;;
                *)
                    LOAD_ARGS+=("$arg")
                    ;;
            esac
            i=$((i + 1))
        done

        if [ -z "$INPUT_FILE" ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} load requires -i <file>" >&2
            exit 1
        fi

        if [ ! -f "$INPUT_FILE" ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} File not found: $INPUT_FILE" >&2
            exit 1
        fi

        run_runtime_command_with_input "$INPUT_FILE" "tar" \
            "$VCONTAINER_RUNTIME_CMD load -i {INPUT}/$(basename "$INPUT_FILE") ${LOAD_ARGS[*]}"
        ;;

    import)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "import"
        # runtime import <tarball> [name:tag] - matches Docker/Podman's import exactly
        # Only accepts tarballs (rootfs archives), not OCI directories
        if [ ${#COMMAND_ARGS[@]} -lt 1 ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} import requires <tarball> [name:tag]" >&2
            echo "For OCI directories, use 'vimport' instead." >&2
            exit 1
        fi

        INPUT_PATH="${COMMAND_ARGS[0]}"
        IMAGE_NAME="${COMMAND_ARGS[1]:-imported:latest}"

        if [ ! -e "$INPUT_PATH" ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Not found: $INPUT_PATH" >&2
            exit 1
        fi

        # Only accept files (tarballs), not directories
        if [ -d "$INPUT_PATH" ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} import only accepts tarballs, not directories" >&2
            echo "For OCI directories, use: $VCONTAINER_RUNTIME_NAME vimport $INPUT_PATH $IMAGE_NAME" >&2
            exit 1
        fi

        run_runtime_command_with_input "$INPUT_PATH" "tar" \
            "$VCONTAINER_RUNTIME_CMD import {INPUT}/$(basename "$INPUT_PATH") $IMAGE_NAME && $VCONTAINER_RUNTIME_CMD images"
        ;;

    vimport)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "vimport"
        # Extended import: handles OCI directories, tarballs, and plain directories
        # Auto-detects format
        if [ ${#COMMAND_ARGS[@]} -lt 1 ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} vimport requires <path> [name:tag]" >&2
            exit 1
        fi

        INPUT_PATH="${COMMAND_ARGS[0]}"
        IMAGE_NAME="${COMMAND_ARGS[1]:-imported:latest}"

        if [ ! -e "$INPUT_PATH" ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Not found: $INPUT_PATH" >&2
            exit 1
        fi

        # Detect input type
        if [ -d "$INPUT_PATH" ]; then
            if [ -f "$INPUT_PATH/index.json" ] || [ -f "$INPUT_PATH/oci-layout" ]; then
                INPUT_TYPE="oci"
                ACTUAL_OCI_PATH="$INPUT_PATH"

                # Check for multi-architecture OCI Image Index
                if is_oci_image_index "$INPUT_PATH"; then
                    available_platforms=$(get_oci_platforms "$INPUT_PATH")
                    [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Multi-arch OCI detected. Available: $available_platforms" >&2

                    # Select manifest for target architecture
                    manifest_digest=$(select_platform_manifest "$INPUT_PATH" "$TARGET_ARCH")
                    if [ -z "$manifest_digest" ]; then
                        echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Architecture $TARGET_ARCH not found in multi-arch image" >&2
                        echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Available platforms: $available_platforms" >&2
                        echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Use --arch <arch> to select a different platform" >&2
                        exit 1
                    fi

                    echo -e "${GREEN}[$VCONTAINER_RUNTIME_NAME]${NC} Selected platform: $(normalize_arch_to_oci "$TARGET_ARCH")/linux (from multi-arch image)" >&2

                    # Extract single-platform OCI to temp directory
                    TEMP_OCI_DIR=$(mktemp -d)
                    trap "rm -rf '$TEMP_OCI_DIR'" EXIT

                    if ! extract_platform_oci "$INPUT_PATH" "$TEMP_OCI_DIR" "$manifest_digest"; then
                        echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Failed to extract platform from multi-arch image" >&2
                        exit 1
                    fi

                    ACTUAL_OCI_PATH="$TEMP_OCI_DIR"
                    [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Extracted to: $TEMP_OCI_DIR" >&2
                else
                    # Single-arch OCI - check architecture before importing
                    if ! check_oci_arch "$INPUT_PATH" "$TARGET_ARCH"; then
                        exit 1
                    fi
                fi

                # Use skopeo to properly import OCI image with full metadata (entrypoint, cmd, etc.)
                # This preserves the container config unlike raw import
                # For multi-arch, we import from the extracted temp directory
                if [ "$ACTUAL_OCI_PATH" = "$INPUT_PATH" ]; then
                    RUNTIME_CMD="skopeo copy oci:{INPUT} ${VCONTAINER_IMPORT_TARGET}$IMAGE_NAME && $VCONTAINER_RUNTIME_CMD images"
                else
                    # Multi-arch: copy extracted OCI to share dir for import
                    # We need to handle this specially since INPUT_PATH differs from actual OCI
                    INPUT_PATH="$ACTUAL_OCI_PATH"
                    RUNTIME_CMD="skopeo copy oci:{INPUT} ${VCONTAINER_IMPORT_TARGET}$IMAGE_NAME && $VCONTAINER_RUNTIME_CMD images"
                fi
            else
                # Directory but not OCI - check if it looks like a deploy/images dir
                # and provide a helpful hint
                if ls "$INPUT_PATH"/*-oci >/dev/null 2>&1; then
                    echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Directory is not an OCI container: $INPUT_PATH" >&2
                    echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Found OCI directories inside. Did you mean one of these?" >&2
                    for oci_dir in "$INPUT_PATH"/*-oci; do
                        if [ -d "$oci_dir" ]; then
                            echo "    $(basename "$oci_dir")" >&2
                        fi
                    done
                    echo "" >&2
                    echo "Example: $VCONTAINER_RUNTIME_NAME vimport $INPUT_PATH/$(ls "$INPUT_PATH" | grep -m1 '\-oci$') myimage:latest" >&2
                    exit 1
                fi
                INPUT_TYPE="dir"
                RUNTIME_CMD="$VCONTAINER_RUNTIME_CMD import {INPUT} $IMAGE_NAME && $VCONTAINER_RUNTIME_CMD images"
            fi
        else
            INPUT_TYPE="tar"
            RUNTIME_CMD="$VCONTAINER_RUNTIME_CMD import {INPUT}/$(basename "$INPUT_PATH") $IMAGE_NAME && $VCONTAINER_RUNTIME_CMD images"
        fi

        run_runtime_command_with_input "$INPUT_PATH" "$INPUT_TYPE" "$RUNTIME_CMD"
        ;;

    save)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "save"
        # runtime save -o <file> <image>
        OUTPUT_FILE=""
        IMAGE_NAME=""
        i=0
        while [ $i -lt ${#COMMAND_ARGS[@]} ]; do
            arg="${COMMAND_ARGS[$i]}"
            case "$arg" in
                -o|--output)
                    i=$((i + 1))
                    OUTPUT_FILE="${COMMAND_ARGS[$i]}"
                    ;;
                *)
                    IMAGE_NAME="$arg"
                    ;;
            esac
            i=$((i + 1))
        done

        if [ -z "$OUTPUT_FILE" ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} save requires -o <file>" >&2
            exit 1
        fi

        if [ -z "$IMAGE_NAME" ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} save requires <image> name" >&2
            exit 1
        fi

        if daemon_is_running; then
            # Use daemon mode with virtio-9p - save to shared dir, then copy to host
            [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Using daemon mode for save" >&2
            SHARE_DIR="${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}/share"

            # Clear share dir and run save command
            rm -rf "$SHARE_DIR"/* 2>/dev/null || true
            run_runtime_command "$VCONTAINER_RUNTIME_CMD save -o /mnt/share/output.tar $IMAGE_NAME"

            # Copy from share dir to output file
            if [ -f "$SHARE_DIR/output.tar" ]; then
                cp "$SHARE_DIR/output.tar" "$OUTPUT_FILE"
                rm -f "$SHARE_DIR/output.tar"
                echo -e "${GREEN}[$VCONTAINER_RUNTIME_NAME]${NC} Saved to $OUTPUT_FILE ($(du -h "$OUTPUT_FILE" | cut -f1))"
            else
                echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Save failed - output not found in shared directory" >&2
                exit 1
            fi
        else
            # Regular mode - use serial output
            RUNNER_ARGS=$(build_runner_args)
            RUNNER_ARGS=$(echo "$RUNNER_ARGS" | sed 's/--output-type storage//')
            "$RUNNER" $RUNNER_ARGS --output-type tar --output "$OUTPUT_FILE" \
                -- "$VCONTAINER_RUNTIME_CMD save -o /tmp/output.tar $IMAGE_NAME"
        fi
        ;;

    tag|rmi)
        if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ]; then
            case "$COMMAND" in
                rmi)
                    [ ${#COMMAND_ARGS[@]} -lt 1 ] && { echo "rmi requires <image>" >&2; exit 1; }
                    IMAGE_NAME="${COMMAND_ARGS[0]}"
                    _vxn_normalized=$(vxn_normalize_image_name "$IMAGE_NAME")
                    _vxn_ref_key=$(vxn_image_ref_key "$_vxn_normalized")
                    _vxn_ref_link="$VXN_IMAGE_CACHE/refs/$_vxn_ref_key"
                    if [ -L "$_vxn_ref_link" ]; then
                        _vxn_store_dir=$(readlink -f "$_vxn_ref_link")
                        rm -f "$_vxn_ref_link"
                        # Remove store dir if no other refs point to it
                        _vxn_other_refs=$(find "$VXN_IMAGE_CACHE/refs" -lname "*/$(basename "$_vxn_store_dir")" 2>/dev/null | wc -l)
                        [ "$_vxn_other_refs" -eq 0 ] && rm -rf "$_vxn_store_dir"
                        echo "Removed: $_vxn_normalized"
                    else
                        echo "Image not found: $_vxn_normalized" >&2; exit 1
                    fi
                    exit 0
                    ;;
                tag)
                    [ ${#COMMAND_ARGS[@]} -lt 2 ] && { echo "tag requires <source> <target>" >&2; exit 1; }
                    _vxn_src_oci=$(vxn_image_cache_lookup "${COMMAND_ARGS[0]}")
                    if [ -z "$_vxn_src_oci" ]; then
                        echo "Image not found: ${COMMAND_ARGS[0]}" >&2; exit 1
                    fi
                    _vxn_target_normalized=$(vxn_normalize_image_name "${COMMAND_ARGS[1]}")
                    _vxn_target_ref_key=$(vxn_image_ref_key "$_vxn_target_normalized")
                    mkdir -p "$VXN_IMAGE_CACHE/refs"
                    _vxn_store_base=$(basename "$_vxn_src_oci")
                    ln -sfn "../store/sha256/$_vxn_store_base" "$VXN_IMAGE_CACHE/refs/$_vxn_target_ref_key"
                    echo "Tagged: $_vxn_target_normalized"
                    exit 0
                    ;;
            esac
        fi
        # Commands that work with existing images
        run_runtime_command "$VCONTAINER_RUNTIME_CMD $COMMAND ${COMMAND_ARGS[*]}"
        ;;

    # Container lifecycle commands
    ps)
        # Xen: list per-container DomUs
        if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ]; then
            printf "%-15s %-25s %-15s %-20s\n" "NAME" "IMAGE" "STATUS" "STARTED"
            for cdir in "$HOME/.vxn/containers"/*/; do
                [ -d "$cdir" ] || continue
                name=$(basename "$cdir")
                ctr_image=$(grep '^IMAGE=' "$cdir/container.meta" 2>/dev/null | cut -d= -f2-)
                ctr_started=$(grep '^STARTED=' "$cdir/container.meta" 2>/dev/null | cut -d= -f2-)
                status=$(vxn_container_status "$name")
                printf "%-15s %-25s %-15s %-20s\n" "$name" "${ctr_image:-unknown}" "$status" "${ctr_started:-unknown}"
            done
            exit 0
        fi

        # List containers and show port forwards if daemon is running
        run_runtime_command "$VCONTAINER_RUNTIME_CMD ps ${COMMAND_ARGS[*]}"
        PS_EXIT=$?

        # Show host port forwards if daemon is running and we have any
        # Skip if -q/--quiet flag is present (only container IDs requested)
        PS_QUIET=false
        for arg in "${COMMAND_ARGS[@]}"; do
            case "$arg" in
                -q|--quiet) PS_QUIET=true; break ;;
            esac
        done

        if [ "$PS_QUIET" = "false" ] && daemon_is_running; then
            pf_file=$(get_port_forward_file)
            if [ -f "$pf_file" ] && [ -s "$pf_file" ]; then
                echo ""
                echo -e "${CYAN}Host Port Forwards (QEMU):${NC}"
                printf "  %-20s %-15s %-15s %-8s\n" "CONTAINER" "HOST PORT" "GUEST PORT" "PROTO"
                while IFS=: read -r name host_port guest_port protocol; do
                    printf "  %-20s %-15s %-15s %-8s\n" "$name" "0.0.0.0:$host_port" "$guest_port" "${protocol:-tcp}"
                done < "$pf_file"
            fi
        fi
        exit $PS_EXIT
        ;;

    rm)
        # Xen: remove per-container DomU state
        if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ]; then
            for arg in "${COMMAND_ARGS[@]}"; do
                case "$arg" in -*) continue ;; esac
                cdir="$(vxn_container_dir "$arg")"
                if [ -d "$cdir" ]; then
                    # Stop if still running
                    if vxn_container_is_running "$arg"; then
                        RUNNER_ARGS=$(build_runner_args)
                        "$RUNNER" $RUNNER_ARGS --daemon-socket-dir "$cdir" --state-dir "$cdir" --daemon-stop 2>/dev/null
                    fi
                    rm -rf "$cdir"
                    echo "$arg"
                fi
            done
            exit 0
        fi

        # Remove containers and cleanup any registered port forwards
        for arg in "${COMMAND_ARGS[@]}"; do
            # Skip flags like -f, --force, etc.
            case "$arg" in
                -*) continue ;;
            esac
            # This is a container name/id - clean up its port forwards
            if daemon_is_running; then
                unregister_port_forwards "$arg"
            fi
        done
        run_runtime_command "$VCONTAINER_RUNTIME_CMD rm ${COMMAND_ARGS[*]}"
        ;;

    logs)
        # Xen: retrieve entrypoint log from DomU
        if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ]; then
            if [ ${#COMMAND_ARGS[@]} -lt 1 ]; then
                echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} logs requires <container>" >&2
                exit 1
            fi
            cname="${COMMAND_ARGS[0]}"
            cdir="$(vxn_container_dir "$cname")"
            if [ -d "$cdir" ] && vxn_container_is_running "$cname"; then
                RUNNER_ARGS=$(build_runner_args)
                "$RUNNER" $RUNNER_ARGS --daemon-socket-dir "$cdir" --state-dir "$cdir" --daemon-send -- "cat /tmp/entrypoint.log 2>/dev/null"
                exit $?
            fi
            echo "Container $cname not running" >&2
            exit 1
        fi

        # View container logs
        run_runtime_command "$VCONTAINER_RUNTIME_CMD logs ${COMMAND_ARGS[*]}"
        ;;

    inspect)
        if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ]; then
            [ ${#COMMAND_ARGS[@]} -lt 1 ] && { echo "inspect requires <image>" >&2; exit 1; }
            _vxn_cached_oci=$(vxn_image_cache_lookup "${COMMAND_ARGS[0]}")
            if [ -n "$_vxn_cached_oci" ]; then
                vxn_image_cache_inspect "$_vxn_cached_oci"
                exit 0
            fi
            # Not in image cache — could be a container name on Xen
            echo "Not found: ${COMMAND_ARGS[0]}" >&2
            exit 1
        fi
        # Inspect container or image
        run_runtime_command "$VCONTAINER_RUNTIME_CMD inspect ${COMMAND_ARGS[*]}"
        ;;

    start|restart|kill|pause|unpause)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "$COMMAND"
        # Container state commands (no special handling needed)
        run_runtime_command "$VCONTAINER_RUNTIME_CMD $COMMAND ${COMMAND_ARGS[*]}"
        ;;

    stop)
        # Xen: stop per-container DomU
        if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && [ -n "${COMMAND_ARGS[0]:-}" ]; then
            cname="${COMMAND_ARGS[0]}"
            cdir="$(vxn_container_dir "$cname")"
            if [ -d "$cdir" ]; then
                RUNNER_ARGS=$(build_runner_args)
                "$RUNNER" $RUNNER_ARGS --daemon-socket-dir "$cdir" --state-dir "$cdir" --daemon-stop
                exit $?
            fi
        fi

        # Stop container and cleanup any registered port forwards
        if [ ${#COMMAND_ARGS[@]} -ge 1 ]; then
            STOP_CONTAINER_NAME="${COMMAND_ARGS[0]}"
            # Remove port forwards for this container (if any)
            if daemon_is_running; then
                unregister_port_forwards "$STOP_CONTAINER_NAME"
            fi
        fi
        run_runtime_command "$VCONTAINER_RUNTIME_CMD stop ${COMMAND_ARGS[*]}"
        ;;

    # Image commands
    commit)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "commit"
        # Commit container to image
        run_runtime_command "$VCONTAINER_RUNTIME_CMD commit ${COMMAND_ARGS[*]}"
        ;;

    history)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "history"
        # Show image history
        run_runtime_command "$VCONTAINER_RUNTIME_CMD history ${COMMAND_ARGS[*]}"
        ;;

    # Registry commands
    push)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "push"
        # Push image to registry
        run_runtime_command "$VCONTAINER_RUNTIME_CMD push ${COMMAND_ARGS[*]}"
        ;;

    search)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "search"
        # Search registries
        run_runtime_command "$VCONTAINER_RUNTIME_CMD search ${COMMAND_ARGS[*]}"
        ;;

    login)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "login"
        # Login needs interactive stdin for password prompt.
        # Use daemon-interactive mode (same as vshell/exec -it).
        if daemon_is_running; then
            RUNNER_ARGS=$(build_runner_args)
            "$RUNNER" $RUNNER_ARGS --daemon-interactive -- "$VCONTAINER_RUNTIME_CMD login ${COMMAND_ARGS[*]}"
        else
            run_runtime_command "$VCONTAINER_RUNTIME_CMD login ${COMMAND_ARGS[*]}"
        fi
        ;;

    logout)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "logout"
        # Logout from registry
        run_runtime_command "$VCONTAINER_RUNTIME_CMD logout ${COMMAND_ARGS[*]}"
        ;;

    # Runtime exec - execute command in running container
    exec)
        if [ ${#COMMAND_ARGS[@]} -lt 2 ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} exec requires <container> <command>" >&2
            exit 1
        fi

        # Xen: exec in per-container DomU
        if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ]; then
            cname="${COMMAND_ARGS[0]}"
            cdir="$(vxn_container_dir "$cname")"
            if [ -d "$cdir" ] && vxn_container_is_running "$cname"; then
                shift_args=("${COMMAND_ARGS[@]:1}")
                exec_cmd="${shift_args[*]}"
                RUNNER_ARGS=$(build_runner_args)
                "$RUNNER" $RUNNER_ARGS --daemon-socket-dir "$cdir" --state-dir "$cdir" --daemon-send -- "$exec_cmd"
                exit $?
            fi
            echo "Container $cname not running" >&2
            exit 1
        fi

        # Check for interactive flags
        EXEC_INTERACTIVE=false
        EXEC_ARGS=()
        for arg in "${COMMAND_ARGS[@]}"; do
            case "$arg" in
                -it|-ti|--interactive|--tty)
                    EXEC_INTERACTIVE=true
                    EXEC_ARGS+=("$arg")
                    ;;
                -i|-t)
                    EXEC_INTERACTIVE=true
                    EXEC_ARGS+=("$arg")
                    ;;
                *)
                    EXEC_ARGS+=("$arg")
                    ;;
            esac
        done

        if [ "$EXEC_INTERACTIVE" = "true" ]; then
            # Interactive exec can use daemon_interactive if daemon is running
            if daemon_is_running; then
                # Use daemon interactive mode - keeps daemon running
                [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Using daemon interactive mode" >&2
                RUNNER_ARGS=$(build_runner_args)
                "$RUNNER" $RUNNER_ARGS --daemon-interactive -- "$VCONTAINER_RUNTIME_CMD exec ${EXEC_ARGS[*]}"
            else
                # No daemon running, use regular QEMU
                RUNNER_ARGS=$(build_runner_args)
                "$RUNNER" $RUNNER_ARGS -- "$VCONTAINER_RUNTIME_CMD exec ${EXEC_ARGS[*]}"
            fi
        else
            # Non-interactive exec via daemon
            run_runtime_command "$VCONTAINER_RUNTIME_CMD exec ${EXEC_ARGS[*]}"
        fi
        ;;

    # VM shell - interactive shell into the VM itself (not a container)
    vshell)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "vshell"
        # Opens a shell directly in the vdkr/vpdmn VM for debugging
        # This runs /bin/sh in the VM, not inside a container
        # Useful for:
        #   - Running docker commands directly to see full error output
        #   - Debugging VM-level issues
        #   - Inspecting the VM filesystem
        if ! daemon_is_running; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} vshell requires daemon mode" >&2
            echo "Start daemon with: $VCONTAINER_RUNTIME_NAME vmemres start" >&2
            exit 1
        fi

        echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Opening VM shell (type 'exit' to return)..." >&2
        RUNNER_ARGS=$(build_runner_args)
        "$RUNNER" $RUNNER_ARGS --daemon-interactive -- "/bin/sh"
        ;;

    # Runtime cp - copy files to/from container
    cp)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "cp"
        if [ ${#COMMAND_ARGS[@]} -lt 2 ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} cp requires <src> <dest>" >&2
            echo "Usage: $VCONTAINER_RUNTIME_NAME cp <container>:<path> <local_path>" >&2
            echo "       $VCONTAINER_RUNTIME_NAME cp <local_path> <container>:<path>" >&2
            exit 1
        fi

        SRC="${COMMAND_ARGS[0]}"
        DEST="${COMMAND_ARGS[1]}"

        # Determine direction: host->container or container->host
        if [[ "$SRC" == *":"* ]] && [[ "$DEST" != *":"* ]]; then
            # Container to host: runtime cp container:/path /local/path
            # Run runtime cp to /mnt/share, then copy from share to host
            CONTAINER_PATH="$SRC"
            HOST_PATH="$DEST"
            SHARE_DIR="${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}/share"

            if daemon_is_running; then
                rm -rf "$SHARE_DIR"/* 2>/dev/null || true
                run_runtime_command "$VCONTAINER_RUNTIME_CMD cp $CONTAINER_PATH /mnt/share/"
                # Find what was copied and move to destination
                if [ -n "$(ls -A "$SHARE_DIR" 2>/dev/null)" ]; then
                    cp -r "$SHARE_DIR"/* "$HOST_PATH" 2>/dev/null || cp -r "$SHARE_DIR"/* "$(dirname "$HOST_PATH")/"
                    rm -rf "$SHARE_DIR"/*
                    echo -e "${GREEN}[$VCONTAINER_RUNTIME_NAME]${NC} Copied to $HOST_PATH"
                else
                    echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Copy failed - no files in share directory" >&2
                    exit 1
                fi
            else
                echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} cp requires daemon mode. Start with: $VCONTAINER_RUNTIME_NAME memres start" >&2
                exit 1
            fi

        elif [[ "$SRC" != *":"* ]] && [[ "$DEST" == *":"* ]]; then
            # Host to container: runtime cp /local/path container:/path
            HOST_PATH="$SRC"
            CONTAINER_PATH="$DEST"

            if [ ! -e "$HOST_PATH" ]; then
                echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Source not found: $HOST_PATH" >&2
                exit 1
            fi

            if daemon_is_running; then
                SHARE_DIR="${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}/share"
                rm -rf "$SHARE_DIR"/* 2>/dev/null || true
                cp -r "$HOST_PATH" "$SHARE_DIR/"
                sync
                BASENAME=$(basename "$HOST_PATH")
                run_runtime_command "$VCONTAINER_RUNTIME_CMD cp /mnt/share/$BASENAME $CONTAINER_PATH"
                rm -rf "$SHARE_DIR"/*
                echo -e "${GREEN}[$VCONTAINER_RUNTIME_NAME]${NC} Copied to $CONTAINER_PATH"
            else
                echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} cp requires daemon mode. Start with: $VCONTAINER_RUNTIME_NAME memres start" >&2
                exit 1
            fi
        else
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Invalid cp syntax. One path must be container:path" >&2
            exit 1
        fi
        ;;

    vconfig)
        # Configuration management (runs on host, not in VM)
        VALID_KEYS="arch timeout state-dir verbose idle-timeout auto-daemon registry"

        if [ ${#COMMAND_ARGS[@]} -lt 1 ]; then
            # Show all config
            echo "$VCONTAINER_RUNTIME_NAME configuration ($CONFIG_FILE):"
            echo ""
            for key in $VALID_KEYS; do
                value=$(config_get "$key" "")
                default=$(config_default "$key")
                if [ -n "$value" ]; then
                    echo "  ${CYAN}$key${NC} = $value"
                else
                    echo "  ${CYAN}$key${NC} = $default ${YELLOW}(default)${NC}"
                fi
            done
            echo ""
            echo "Config directory: $CONFIG_DIR"
        else
            KEY="${COMMAND_ARGS[0]}"
            VALUE="${COMMAND_ARGS[1]:-}"

            # Validate key
            if ! echo "$VALID_KEYS" | grep -qw "$KEY"; then
                echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Unknown config key: $KEY" >&2
                echo "Valid keys: $VALID_KEYS" >&2
                exit 1
            fi

            if [ -z "$VALUE" ]; then
                # Get value
                current=$(config_get "$KEY" "")
                default=$(config_default "$KEY")
                if [ -n "$current" ]; then
                    echo "$current"
                else
                    echo "$default"
                fi
            elif [ "$VALUE" = "--reset" ]; then
                # Reset to default
                config_unset "$KEY"
                echo "Reset $KEY to default: $(config_default "$KEY")"
            else
                # Validate value for arch
                if [ "$KEY" = "arch" ]; then
                    case "$VALUE" in
                        aarch64|x86_64) ;;
                        *)
                            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Invalid architecture: $VALUE" >&2
                            echo "Valid values: aarch64, x86_64" >&2
                            exit 1
                            ;;
                    esac
                fi

                # Validate value for verbose
                if [ "$KEY" = "verbose" ]; then
                    case "$VALUE" in
                        true|false) ;;
                        *)
                            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Invalid verbose value: $VALUE" >&2
                            echo "Valid values: true, false" >&2
                            exit 1
                            ;;
                    esac
                fi

                # Set value
                config_set "$KEY" "$VALUE"
                echo "Set $KEY = $VALUE"
            fi
        fi
        ;;

    clean)
        # DEPRECATED: Use 'vstorage clean' instead
        echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} DEPRECATED: 'clean' is deprecated, use 'vstorage clean' instead" >&2
        echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC}   vstorage clean          - clean current architecture" >&2
        echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC}   vstorage clean <arch>   - clean specific architecture" >&2
        echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC}   vstorage clean --all    - clean all architectures" >&2
        echo "" >&2

        # Still perform the clean for now (will be removed in future version)
        CLEAN_DIR="${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}"
        if [ -d "$CLEAN_DIR" ]; then
            # Stop memres if running
            if [ -f "$CLEAN_DIR/daemon.pid" ]; then
                pid=$(cat "$CLEAN_DIR/daemon.pid" 2>/dev/null)
                if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                    echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Stopping memres (PID $pid)..."
                    kill "$pid" 2>/dev/null || true
                fi
            fi
            echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Removing state directory: $CLEAN_DIR"
            rm -rf "$CLEAN_DIR"
            echo -e "${GREEN}[$VCONTAINER_RUNTIME_NAME]${NC} State cleaned. Next run will start fresh."
        else
            echo -e "${GREEN}[$VCONTAINER_RUNTIME_NAME]${NC} No state directory found for $TARGET_ARCH"
        fi
        ;;

    info)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "info"
        run_runtime_command "$VCONTAINER_RUNTIME_CMD info"
        ;;

    version)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "version"
        run_runtime_command "$VCONTAINER_RUNTIME_CMD version"
        ;;

    system)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "system"
        # Passthrough to runtime system commands (df, prune, events, etc.)
        if [ ${#COMMAND_ARGS[@]} -lt 1 ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} system requires a subcommand: df, prune, events, info" >&2
            exit 1
        fi
        run_runtime_command "$VCONTAINER_RUNTIME_CMD system ${COMMAND_ARGS[*]}"
        ;;

    vstorage)
        # Host-side storage management (runs on host, not in VM)
        if [ ${#COMMAND_ARGS[@]} -lt 1 ]; then
            STORAGE_CMD="list"
        else
            STORAGE_CMD="${COMMAND_ARGS[0]}"
        fi

        # When --state-dir is passed, scan its parent as the storage root
        # (STATE_DIR is an arch subdir like ~/.vpdmn-test/x86_64, so the
        # parent ~/.vpdmn-test/ is the root containing all arch dirs).
        VSTORAGE_ROOT="$DEFAULT_STATE_DIR"
        if [ -n "$STATE_DIR" ]; then
            VSTORAGE_ROOT="$(dirname "$STATE_DIR")"
        fi

        case "$STORAGE_CMD" in
            list)
                echo "$VCONTAINER_RUNTIME_NAME storage directories:"
                echo ""
                found=0
                for state_dir in "$VSTORAGE_ROOT"/*/; do
                    [ -d "$state_dir" ] || continue
                    found=1
                    instance=$(basename "$state_dir")
                    size=$(du -sh "$state_dir" 2>/dev/null | cut -f1)

                    echo "  ${CYAN}$instance${NC}"
                    echo "    Path:   $state_dir"
                    echo "    Size:   $size"

                    # Check if memres is running
                    if [ -f "$state_dir/daemon.pid" ]; then
                        pid=$(cat "$state_dir/daemon.pid")
                        if [ -d "/proc/$pid" ]; then
                            echo "    Status: ${GREEN}memres running${NC} (PID $pid)"
                        else
                            echo "    Status: stopped"
                        fi
                    else
                        echo "    Status: no memres"
                    fi
                    echo ""
                done
                if [ $found -eq 0 ]; then
                    echo "  (no storage directories found)"
                    echo ""
                fi

                # Total size
                if [ -d "$VSTORAGE_ROOT" ] && [ $found -gt 0 ]; then
                    total=$(du -sh "$VSTORAGE_ROOT" 2>/dev/null | cut -f1)
                    echo "Total: $total"
                fi
                ;;

            path)
                # Show path for specific or current architecture
                arch="${COMMAND_ARGS[1]:-$TARGET_ARCH}"
                echo "${STATE_DIR:-$DEFAULT_STATE_DIR/$arch}"
                ;;

            df)
                # Detailed breakdown
                for state_dir in "$VSTORAGE_ROOT"/*/; do
                    [ -d "$state_dir" ] || continue
                    instance=$(basename "$state_dir")
                    echo "${BOLD}$instance${NC}:"

                    # Show individual components
                    for item in "$VCONTAINER_STATE_FILE" share; do
                        if [ -e "$state_dir/$item" ]; then
                            item_size=$(du -sh "$state_dir/$item" 2>/dev/null | cut -f1)
                            printf "  %-20s %s\n" "$item" "$item_size"
                        fi
                    done
                    echo ""
                done
                ;;

            clean)
                # Clean storage for specific arch or all
                arch="${COMMAND_ARGS[1]:-}"
                if [ "$arch" = "--all" ]; then
                    # Stop any running memres first
                    for pid_file in "$VSTORAGE_ROOT"/*/daemon.pid; do
                        [ -f "$pid_file" ] || continue
                        pid=$(cat "$pid_file" 2>/dev/null)
                        if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                            echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Stopping memres (PID $pid)..."
                            kill "$pid" 2>/dev/null || true
                        fi
                    done
                    echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Removing all storage directories..."
                    rm -rf "$VSTORAGE_ROOT"
                    echo -e "${GREEN}[$VCONTAINER_RUNTIME_NAME]${NC} All storage cleaned."
                elif [ -n "$arch" ]; then
                    # Clean specific arch
                    clean_dir="$VSTORAGE_ROOT/$arch"
                    if [ -d "$clean_dir" ]; then
                        # Stop memres if running
                        if [ -f "$clean_dir/daemon.pid" ]; then
                            pid=$(cat "$clean_dir/daemon.pid" 2>/dev/null)
                            if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                                echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Stopping memres (PID $pid)..."
                                kill "$pid" 2>/dev/null || true
                            fi
                        fi
                        rm -rf "$clean_dir"
                        echo -e "${GREEN}[$VCONTAINER_RUNTIME_NAME]${NC} Cleaned: $clean_dir"
                    else
                        echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Not found: $clean_dir"
                    fi
                else
                    # Clean current arch (same as existing clean command)
                    clean_dir="${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}"
                    if [ -d "$clean_dir" ]; then
                        # Stop memres if running
                        if [ -f "$clean_dir/daemon.pid" ]; then
                            pid=$(cat "$clean_dir/daemon.pid" 2>/dev/null)
                            if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                                echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Stopping memres (PID $pid)..."
                                kill "$pid" 2>/dev/null || true
                            fi
                        fi
                        rm -rf "$clean_dir"
                        echo -e "${GREEN}[$VCONTAINER_RUNTIME_NAME]${NC} Cleaned: $clean_dir"
                    else
                        echo -e "${GREEN}[$VCONTAINER_RUNTIME_NAME]${NC} No storage directory found for $TARGET_ARCH"
                    fi
                fi
                ;;

            *)
                echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Unknown vstorage subcommand: $STORAGE_CMD" >&2
                echo "Usage: $VCONTAINER_RUNTIME_NAME vstorage [list|path|df|clean]" >&2
                echo "" >&2
                echo "Subcommands:" >&2
                echo "  list              List all storage directories with details" >&2
                echo "  path [arch]       Show path to storage directory" >&2
                echo "  df                Show detailed disk usage breakdown" >&2
                echo "  clean [arch|--all] Clean storage directories" >&2
                exit 1
                ;;
        esac
        ;;

    vrun)
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && vxn_unsupported "vrun"
        # Extended run: run a command in a container (runtime-like syntax)
        # Usage: <tool> vrun [options] <image> [command] [args...]
        # Options:
        #   -it, -i, -t              Interactive mode with TTY
        #   --network, -n            Enable networking
        #   -p <host>:<guest>        Forward port from host to container
        #   -v <host>:<container>    Mount host directory in container
        #
        # Parse vrun-specific options (allows runtime-like: vdkr vrun -it alpine /bin/sh)
        VRUN_VOLUMES=()
        HAS_VOLUMES=false

        while [ ${#COMMAND_ARGS[@]} -gt 0 ]; do
            case "${COMMAND_ARGS[0]}" in
                -it|--interactive)
                    INTERACTIVE="true"
                    COMMAND_ARGS=("${COMMAND_ARGS[@]:1}")
                    ;;
                -i|-t)
                    INTERACTIVE="true"
                    COMMAND_ARGS=("${COMMAND_ARGS[@]:1}")
                    ;;
                --no-network)
                    NETWORK="false"
                    COMMAND_ARGS=("${COMMAND_ARGS[@]:1}")
                    ;;
                -p|--publish)
                    # Port forward: -p 8080:80 or -p 8080:80/tcp
                    NETWORK="true"  # Port forwarding requires networking
                    if [ ${#COMMAND_ARGS[@]} -lt 2 ]; then
                        echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} -p requires <host_port>:<container_port>" >&2
                        exit 1
                    fi
                    PORT_FORWARDS+=("${COMMAND_ARGS[1]}")
                    COMMAND_ARGS=("${COMMAND_ARGS[@]:2}")
                    ;;
                -v|--volume)
                    # Volume mount: -v /host/path:/container/path[:ro|:rw]
                    if [ ${#COMMAND_ARGS[@]} -lt 2 ]; then
                        echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} -v requires <host_path>:<container_path>" >&2
                        exit 1
                    fi
                    VRUN_VOLUMES+=("-v" "${COMMAND_ARGS[1]}")
                    HAS_VOLUMES=true
                    COMMAND_ARGS=("${COMMAND_ARGS[@]:2}")
                    ;;
                -*)
                    # Unknown option - stop parsing, rest goes to container
                    break
                    ;;
                *)
                    # Not an option - this is the image name
                    break
                    ;;
            esac
        done

        # Volume mounts require daemon mode
        if [ "$HAS_VOLUMES" = "true" ] && ! daemon_is_running; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Volume mounts require daemon mode. Start with: $VCONTAINER_RUNTIME_NAME memres start" >&2
            exit 1
        fi

        if [ ${#COMMAND_ARGS[@]} -lt 1 ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} vrun requires <image> [command] [args...]" >&2
            echo "Usage: $VCONTAINER_RUNTIME_NAME vrun [options] <image> [command] [args...]" >&2
            echo "" >&2
            echo "Options:" >&2
            echo "  -it, -i, -t              Interactive mode with TTY" >&2
            echo "  --no-network             Disable networking" >&2
            echo "  -p <host>:<container>    Forward port" >&2
            echo "  -v <host>:<container>    Mount host directory in container" >&2
            echo "" >&2
            echo "Examples:" >&2
            echo "  $VCONTAINER_RUNTIME_NAME vrun alpine /bin/ls -la" >&2
            echo "  $VCONTAINER_RUNTIME_NAME vrun -it alpine /bin/sh" >&2
            echo "  $VCONTAINER_RUNTIME_NAME vrun -p 8080:80 nginx:latest" >&2
            echo "  $VCONTAINER_RUNTIME_NAME vrun -v /tmp/data:/data alpine cat /data/file.txt" >&2
            exit 1
        fi

        IMAGE_NAME="${COMMAND_ARGS[0]}"
        CONTAINER_CMD=""

        # Build command from remaining args
        for ((i=1; i<${#COMMAND_ARGS[@]}; i++)); do
            if [ -n "$CONTAINER_CMD" ]; then
                CONTAINER_CMD="$CONTAINER_CMD ${COMMAND_ARGS[$i]}"
            else
                CONTAINER_CMD="${COMMAND_ARGS[$i]}"
            fi
        done

        # Prepare volume mounts if any
        VOLUME_OPTS=""
        if [ "$HAS_VOLUMES" = "true" ]; then
            [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Preparing volume mounts..." >&2

            # Parse and prepare volumes (transforms host paths to guest paths)
            parse_and_prepare_volumes "${VRUN_VOLUMES[@]}" || {
                cleanup_volumes
                exit 1
            }

            # Build volume options string from transformed args
            VOLUME_OPTS="${TRANSFORMED_VOLUME_ARGS[*]}"
            [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Volume options: $VOLUME_OPTS" >&2
        fi

        # Build runtime run command
        RUNTIME_RUN_OPTS="--rm"
        if [ "$INTERACTIVE" = "true" ]; then
            RUNTIME_RUN_OPTS="$RUNTIME_RUN_OPTS -it"
        fi
        # Use bridge networking (Docker's default) with VM's DNS
        # Each container gets its own IP on 172.17.0.0/16
        if [ "$NETWORK" = "true" ]; then
            RUNTIME_RUN_OPTS="$RUNTIME_RUN_OPTS --dns=10.0.2.3 --dns=8.8.8.8"
        fi

        # Add volume mounts
        if [ -n "$VOLUME_OPTS" ]; then
            RUNTIME_RUN_OPTS="$RUNTIME_RUN_OPTS $VOLUME_OPTS"
        fi

        if [ -n "$CONTAINER_CMD" ]; then
            # Clear entrypoint when command provided - ensures command runs directly
            # without being passed to image's entrypoint (e.g., prevents 'sh /bin/echo')
            RUNTIME_CMD="$VCONTAINER_RUNTIME_CMD run $RUNTIME_RUN_OPTS --entrypoint '' $IMAGE_NAME $CONTAINER_CMD"
        else
            RUNTIME_CMD="$VCONTAINER_RUNTIME_CMD run $RUNTIME_RUN_OPTS $IMAGE_NAME"
        fi

        [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Runtime command: $RUNTIME_CMD" >&2

        # Use daemon mode for non-interactive runs
        if [ "$INTERACTIVE" = "true" ]; then
            # Interactive mode with volumes still needs to stop daemon (volumes use share dir)
            # Interactive mode without volumes can use daemon_interactive (faster)
            if [ "$HAS_VOLUMES" = "false" ] && daemon_is_running; then
                # Use daemon interactive mode - keeps daemon running
                [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Using daemon interactive mode" >&2
                RUNNER_ARGS=$(build_runner_args)
                "$RUNNER" $RUNNER_ARGS --daemon-interactive -- "$RUNTIME_CMD"
                exit $?
            else
                # Fall back to regular QEMU for interactive (stop daemon if running)
                DAEMON_WAS_RUNNING=false
                if daemon_is_running; then
                    DAEMON_WAS_RUNNING=true
                    echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Stopping daemon for interactive mode..." >&2
                    "$RUNNER" --state-dir "${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}" --daemon-stop >/dev/null 2>&1 || true
                    sleep 1
                fi
                RUNNER_ARGS=$(build_runner_args)
                "$RUNNER" $RUNNER_ARGS -- "$RUNTIME_CMD"
                VRUN_EXIT=$?

                # Sync volumes back after container exits
                if [ "$HAS_VOLUMES" = "true" ]; then
                    sync_volumes_back
                    cleanup_volumes
                fi

                # Restart daemon if it was running before
                if [ "$DAEMON_WAS_RUNNING" = "true" ]; then
                    echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Restarting daemon..." >&2
                    "$RUNNER" $RUNNER_ARGS --daemon-start >/dev/null 2>&1 || true
                fi

                exit $VRUN_EXIT
            fi
        else
            # Non-interactive can use daemon mode
            run_runtime_command "$RUNTIME_CMD"
            VRUN_EXIT=$?

            # Sync volumes back after container exits
            if [ "$HAS_VOLUMES" = "true" ]; then
                sync_volumes_back
                cleanup_volumes
            fi

            exit $VRUN_EXIT
        fi
        ;;

    run)
        # Runtime run command - mirrors 'docker/podman run' syntax
        # Usage: <tool> run [options] <image> [command]
        # Automatically prepends 'runtime run' to the arguments
        # Supports volume mounts with -v (requires daemon mode)
        #
        # NOTE: --network=host is added by default because Docker runs with
        # --bridge=none inside the VM. Users can override with --network=none
        # if they truly want no networking.
        if [ ${#COMMAND_ARGS[@]} -eq 0 ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} run requires an image" >&2
            echo "Usage: $VCONTAINER_RUNTIME_NAME run [options] <image> [command]" >&2
            echo "" >&2
            echo "Examples:" >&2
            echo "  $VCONTAINER_RUNTIME_NAME run alpine /bin/echo hello" >&2
            echo "  $VCONTAINER_RUNTIME_NAME run -it alpine /bin/sh" >&2
            echo "  $VCONTAINER_RUNTIME_NAME run --rm -e FOO=bar myapp:latest" >&2
            echo "  $VCONTAINER_RUNTIME_NAME run -v /tmp/data:/data alpine cat /data/file.txt" >&2
            exit 1
        fi

        # vxn (Xen): ephemeral mode by default.
        # Detached mode (-d) uses per-container DomU with daemon loop instead.
        if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ]; then
            # Detached flag is parsed below; defer NO_DAEMON until after flag parsing
            :
        fi

        # Check if any volume mounts, network, port forwards, or detach are present
        RUN_HAS_VOLUMES=false
        RUN_HAS_NETWORK=false
        RUN_HAS_PORT_FORWARDS=false
        RUN_IS_DETACHED=false
        RUN_CONTAINER_NAME=""
        RUN_PORT_FORWARDS=()

        # Parse COMMAND_ARGS to extract relevant flags
        i=0
        prev_arg=""
        for arg in "${COMMAND_ARGS[@]}"; do
            case "$arg" in
                -v|--volume)
                    RUN_HAS_VOLUMES=true
                    ;;
                --network=*|--net=*)
                    RUN_HAS_NETWORK=true
                    ;;
                -p|--publish)
                    RUN_HAS_PORT_FORWARDS=true
                    ;;
                -d|--detach)
                    RUN_IS_DETACHED=true
                    ;;
                --name=*)
                    RUN_CONTAINER_NAME="${arg#--name=}"
                    ;;
            esac
            # Check if previous arg was -p or --publish
            if [ "$prev_arg" = "-p" ] || [ "$prev_arg" = "--publish" ]; then
                # arg is the port specification (e.g., 8080:80)
                RUN_PORT_FORWARDS+=("$arg")
            fi
            # Check if previous arg was --name
            if [ "$prev_arg" = "--name" ]; then
                RUN_CONTAINER_NAME="$arg"
            fi
            prev_arg="$arg"
            i=$((i + 1))
        done

        # Xen: non-detached runs use ephemeral mode unless memres is running
        if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && [ "$RUN_IS_DETACHED" != "true" ]; then
            if daemon_is_running; then
                NO_DAEMON=false
            else
                NO_DAEMON=true
            fi
        fi

        # Volume mounts require daemon mode
        if [ "$RUN_HAS_VOLUMES" = "true" ] && ! daemon_is_running; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Volume mounts require daemon mode. Start with: $VCONTAINER_RUNTIME_NAME memres start" >&2
            exit 1
        fi

        # Transform volume mounts if present
        if [ "$RUN_HAS_VOLUMES" = "true" ]; then
            [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Preparing volume mounts for run command..." >&2

            # Parse and prepare volumes (transforms host paths to guest paths)
            parse_and_prepare_volumes "${COMMAND_ARGS[@]}" || {
                cleanup_volumes
                exit 1
            }
            # Update COMMAND_ARGS with transformed values
            COMMAND_ARGS=("${TRANSFORMED_VOLUME_ARGS[@]}")
        fi

        # Build runtime run command from args
        # Note: -it may have been consumed by global parser, so add it back if INTERACTIVE is set
        # Use bridge networking (Docker's default) - each container gets 172.17.0.x IP
        # User can override with --network=host for legacy behavior
        RUN_NETWORK_OPTS=""
        if [ "$RUN_HAS_NETWORK" = "false" ]; then
            RUN_NETWORK_OPTS="--dns=10.0.2.3 --dns=8.8.8.8"
            [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Using default bridge networking" >&2
        fi

        if [ "$INTERACTIVE" = "true" ]; then
            RUNTIME_CMD="$VCONTAINER_RUNTIME_CMD run -it $RUN_NETWORK_OPTS ${COMMAND_ARGS[*]}"
        else
            RUNTIME_CMD="$VCONTAINER_RUNTIME_CMD run $RUN_NETWORK_OPTS ${COMMAND_ARGS[*]}"
        fi

        if [ "$INTERACTIVE" = "true" ]; then
            # Interactive mode with volumes still needs to stop daemon (volumes use share dir)
            # Interactive mode without volumes can use daemon_interactive (faster)
            if [ "$NO_DAEMON" != "true" ] && [ "$RUN_HAS_VOLUMES" = "false" ] && daemon_is_running; then
                # Use daemon interactive mode - keeps daemon running
                [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Using daemon interactive mode" >&2
                RUNNER_ARGS=$(build_runner_args)
                "$RUNNER" $RUNNER_ARGS --daemon-interactive -- "$RUNTIME_CMD"
                exit $?
            else
                # Fall back to regular QEMU for interactive (stop daemon if running)
                DAEMON_WAS_RUNNING=false
                if daemon_is_running; then
                    DAEMON_WAS_RUNNING=true
                    echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Stopping daemon for interactive mode..." >&2
                    "$RUNNER" --state-dir "${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}" --daemon-stop >/dev/null 2>&1 || true
                    sleep 1
                fi
                RUNNER_ARGS=$(build_runner_args)
                "$RUNNER" $RUNNER_ARGS -- "$RUNTIME_CMD"
                RUN_EXIT=$?

                # Sync volumes back after container exits
                if [ "$RUN_HAS_VOLUMES" = "true" ]; then
                    sync_volumes_back
                    cleanup_volumes
                fi

                # Restart daemon if it was running before
                if [ "$DAEMON_WAS_RUNNING" = "true" ]; then
                    echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Restarting daemon..." >&2
                    "$RUNNER" $RUNNER_ARGS --daemon-start >/dev/null 2>&1 || true
                fi

                exit $RUN_EXIT
            fi
        else
            # Non-interactive - use daemon mode when available

            # Xen detached mode: per-container DomU with daemon loop
            if [ "$RUN_IS_DETACHED" = "true" ] && [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ]; then
                # Generate name if not provided
                [ -z "$RUN_CONTAINER_NAME" ] && RUN_CONTAINER_NAME="$(cat /proc/sys/kernel/random/uuid | cut -c1-8)"

                # Per-container state dir
                VXN_CTR_DIR="$HOME/.vxn/containers/$RUN_CONTAINER_NAME"
                mkdir -p "$VXN_CTR_DIR"

                # Build runner args with per-container state/socket dir
                RUNNER_ARGS=$(build_runner_args)
                RUNNER_ARGS="$RUNNER_ARGS --daemon-socket-dir $VXN_CTR_DIR --state-dir $VXN_CTR_DIR"
                RUNNER_ARGS="$RUNNER_ARGS --container-name $RUN_CONTAINER_NAME"

                # Start per-container DomU (daemon mode + initial command)
                "$RUNNER" $RUNNER_ARGS --daemon-start -- "$RUNTIME_CMD"

                if [ $? -eq 0 ]; then
                    # Save metadata — extract image name (last positional arg before any cmd)
                    local_image=""
                    local_found_image=false
                    local_skip_next=false
                    for arg in "${COMMAND_ARGS[@]}"; do
                        if [ "$local_skip_next" = "true" ]; then
                            local_skip_next=false
                            continue
                        fi
                        case "$arg" in
                            --rm|--detach|-d|-i|--interactive|-t|--tty|--privileged|-it) ;;
                            -p|--publish|-v|--volume|-e|--env|--name|--network|-w|--workdir|--entrypoint|-m|--memory|--cpus)
                                local_skip_next=true ;;
                            --publish=*|--volume=*|--env=*|--name=*|--network=*|--workdir=*|--entrypoint=*|--memory=*|--cpus=*) ;;
                            -*)  ;;
                            *)
                                if [ "$local_found_image" = "false" ]; then
                                    local_image="$arg"
                                    local_found_image=true
                                fi
                                ;;
                        esac
                    done
                    echo "IMAGE=${local_image}" > "$VXN_CTR_DIR/container.meta"
                    echo "COMMAND=$RUNTIME_CMD" >> "$VXN_CTR_DIR/container.meta"
                    echo "STARTED=$(date -Iseconds)" >> "$VXN_CTR_DIR/container.meta"
                    echo "$RUN_CONTAINER_NAME"
                else
                    rm -rf "$VXN_CTR_DIR"
                    exit 1
                fi
                exit 0
            fi

            # Xen memres mode: dispatch container to persistent DomU
            if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] && [ "$NO_DAEMON" != "true" ] && daemon_is_running; then
                [ "$VERBOSE" = "true" ] && echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Using memres DomU" >&2
                RUNNER_ARGS=$(build_runner_args)
                "$RUNNER" $RUNNER_ARGS --daemon-run -- "$RUNTIME_CMD"
                exit $?
            fi

            # For detached containers with port forwards, add them dynamically via QMP
            if [ "$RUN_IS_DETACHED" = "true" ] && [ "$RUN_HAS_PORT_FORWARDS" = "true" ] && daemon_is_running; then
                # Generate container name if not provided (needed for port tracking)
                if [ -z "$RUN_CONTAINER_NAME" ]; then
                    # Generate a random name like docker does
                    RUN_CONTAINER_NAME="$(cat /proc/sys/kernel/random/uuid | cut -c1-12)"
                    # Update COMMAND_ARGS to include the generated name
                    RUNTIME_CMD="$VCONTAINER_RUNTIME_CMD run --name=$RUN_CONTAINER_NAME $RUN_NETWORK_OPTS ${COMMAND_ARGS[*]}"
                fi

                # Add port forwards via QMP and register them
                for port_spec in "${RUN_PORT_FORWARDS[@]}"; do
                    # Parse port specification: [host_ip:]host_port:container_port[/protocol]
                    # Examples: 8080:80, 127.0.0.1:8080:80, 8080:80/tcp, 8080:80/udp
                    spec="$port_spec"
                    protocol="tcp"
                    host_port=""
                    guest_port=""

                    # Extract protocol if present
                    if echo "$spec" | grep -q '/'; then
                        protocol="${spec##*/}"
                        spec="${spec%/*}"
                    fi

                    # Count colons to determine format
                    colon_count=$(echo "$spec" | tr -cd ':' | wc -c)
                    if [ "$colon_count" -eq 2 ]; then
                        # Format: host_ip:host_port:container_port (ignore host_ip for now)
                        host_port=$(echo "$spec" | cut -d: -f2)
                        guest_port=$(echo "$spec" | cut -d: -f3)
                    else
                        # Format: host_port:container_port
                        host_port=$(echo "$spec" | cut -d: -f1)
                        guest_port=$(echo "$spec" | cut -d: -f2)
                    fi

                    if [ -n "$host_port" ] && [ -n "$guest_port" ]; then
                        if qmp_add_hostfwd "$host_port" "$guest_port" "$protocol"; then
                            register_port_forward "$RUN_CONTAINER_NAME" "$host_port" "$guest_port" "$protocol"
                        else
                            echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Warning: Could not add port forward ${host_port}:${guest_port}" >&2
                        fi
                    fi
                done
            fi

            run_runtime_command "$RUNTIME_CMD"
            RUN_EXIT=$?

            # Sync volumes back after container exits
            if [ "$RUN_HAS_VOLUMES" = "true" ]; then
                sync_volumes_back
                cleanup_volumes
            fi

            exit $RUN_EXIT
        fi
        ;;

    # Memory resident subcommand: <tool> memres start|stop|restart|status
    # vmemres is the preferred name (v prefix for tool-specific commands)
    memres|vmemres)
        if [ ${#COMMAND_ARGS[@]} -lt 1 ]; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} memres requires a subcommand: start, stop, restart, status, list" >&2
            exit 1
        fi

        MEMRES_CMD="${COMMAND_ARGS[0]}"

        # Parse memres-specific options (after the subcommand)
        MEMRES_ARGS=("${COMMAND_ARGS[@]:1}")
        i=0
        while [ $i -lt ${#MEMRES_ARGS[@]} ]; do
            arg="${MEMRES_ARGS[$i]}"
            case "$arg" in
                -p|--publish)
                    # Port forward: -p 8080:80 or -p 8080:80/tcp
                    i=$((i + 1))
                    if [ $i -ge ${#MEMRES_ARGS[@]} ]; then
                        echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} -p requires <host_port>:<container_port>" >&2
                        exit 1
                    fi
                    PORT_FORWARDS+=("${MEMRES_ARGS[$i]}")
                    ;;
            esac
            i=$((i + 1))
        done

        RUNNER_ARGS=$(build_runner_args)

        case "$MEMRES_CMD" in
            start)
                if daemon_is_running; then
                    echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} A memres instance is already running for $TARGET_ARCH"
                    echo ""
                    "$RUNNER" $RUNNER_ARGS --daemon-status
                    echo ""
                    echo "Options:"
                    echo "  1) Restart with new settings (stops current instance)"
                    echo "  2) Start additional instance with different --state-dir"
                    echo "  3) Cancel"
                    echo ""
                    read -p "Choice [1-3]: " choice
                    case "$choice" in
                        1)
                            echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Restarting memres..."
                            "$RUNNER" $RUNNER_ARGS --daemon-stop
                            sleep 1
                            "$RUNNER" $RUNNER_ARGS --daemon-start
                            ;;
                        2)
                            echo ""
                            echo "To start an additional instance, use -I <name>:"
                            echo "  $VCONTAINER_RUNTIME_NAME -I web memres start -p 8080:80"
                            echo "  $VCONTAINER_RUNTIME_NAME -I api memres start -p 3000:3000"
                            echo ""
                            echo "Then interact with it:"
                            echo "  $VCONTAINER_RUNTIME_NAME -I web images"
                            echo ""
                            exit 0
                            ;;
                        *)
                            echo "Cancelled."
                            exit 0
                            ;;
                    esac
                else
                    "$RUNNER" $RUNNER_ARGS --daemon-start
                fi
                ;;
            stop)
                # Clear port forward registry when stopping daemon
                pf_file=$(get_port_forward_file)
                if [ -f "$pf_file" ]; then
                    rm -f "$pf_file"
                fi
                "$RUNNER" $RUNNER_ARGS --daemon-stop
                ;;
            restart)
                # Stop if running and clear port forward registry
                pf_file=$(get_port_forward_file)
                if [ -f "$pf_file" ]; then
                    rm -f "$pf_file"
                fi
                "$RUNNER" $RUNNER_ARGS --daemon-stop 2>/dev/null || true

                # Clean if --clean was passed
                for arg in "${COMMAND_ARGS[@]:1}"; do
                    if [ "$arg" = "--clean" ]; then
                        CLEAN_DIR="${STATE_DIR:-$DEFAULT_STATE_DIR/$TARGET_ARCH}"
                        if [ -d "$CLEAN_DIR" ]; then
                            echo -e "${YELLOW}[$VCONTAINER_RUNTIME_NAME]${NC} Cleaning state directory: $CLEAN_DIR"
                            rm -rf "$CLEAN_DIR"
                        fi
                        break
                    fi
                done

                # Start
                "$RUNNER" $RUNNER_ARGS --daemon-start
                ;;
            status)
                "$RUNNER" $RUNNER_ARGS --daemon-status
                ;;
            list)
                # Show all running memres instances
                echo "Running memres instances:"
                echo ""
                found=0
                tracked_pids=""

                # Xen: check for vxn domains via xl list
                if [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ]; then
                    for domname_file in "$DEFAULT_STATE_DIR"/*/daemon.domname; do
                        [ -f "$domname_file" ] || continue
                        domname=$(cat "$domname_file" 2>/dev/null)
                        if [ -n "$domname" ] && xl list "$domname" >/dev/null 2>&1; then
                            instance_dir=$(dirname "$domname_file")
                            instance_name=$(basename "$instance_dir")
                            echo "  ${CYAN}$instance_name${NC}"
                            echo "    Domain: $domname"
                            echo "    State: $instance_dir"
                            if [ -f "$instance_dir/daemon.pty" ]; then
                                echo "    PTY: $(cat "$instance_dir/daemon.pty")"
                            fi
                            echo ""
                            found=$((found + 1))
                        fi
                    done

                    # Also check per-container DomUs
                    if [ -d "$HOME/.vxn/containers" ]; then
                        for meta_file in "$HOME/.vxn/containers"/*/container.meta; do
                            [ -f "$meta_file" ] || continue
                            ctr_dir=$(dirname "$meta_file")
                            ctr_name=$(basename "$ctr_dir")
                            if vxn_container_is_running "$ctr_name"; then
                                image=$(grep '^IMAGE=' "$meta_file" 2>/dev/null | cut -d= -f2)
                                started=$(grep '^STARTED=' "$meta_file" 2>/dev/null | cut -d= -f2)
                                echo "  ${CYAN}$ctr_name${NC} (per-container DomU)"
                                echo "    Image: ${image:-(unknown)}"
                                echo "    Started: ${started:-(unknown)}"
                                echo "    State: $ctr_dir"
                                echo ""
                                found=$((found + 1))
                            fi
                        done
                    fi

                    if [ $found -eq 0 ]; then
                        echo "  (none)"
                    fi

                    # Check for orphan vxn domains
                    echo ""
                    echo "Checking for orphan Xen domains..."
                    orphans=""
                    for domname in $(xl list 2>/dev/null | awk '/^vxn-/{print $1}'); do
                        tracked=false
                        for df in "$DEFAULT_STATE_DIR"/*/daemon.domname "$HOME"/.vxn/containers/*/daemon.domname; do
                            [ -f "$df" ] || continue
                            if [ "$(cat "$df" 2>/dev/null)" = "$domname" ]; then
                                tracked=true
                                break
                            fi
                        done
                        if [ "$tracked" != "true" ]; then
                            orphans="$orphans $domname"
                        fi
                    done

                    if [ -n "$orphans" ]; then
                        echo -e "${YELLOW}Orphan vxn domains found:${NC}"
                        for odom in $orphans; do
                            echo "  ${RED}$odom${NC}"
                            echo "    Destroy with: xl destroy $odom"
                        done
                    else
                        echo "  (no orphans found)"
                    fi
                else
                    # QEMU: check PID files
                    for pid_file in "$DEFAULT_STATE_DIR"/*/daemon.pid; do
                        [ -f "$pid_file" ] || continue
                        pid=$(cat "$pid_file" 2>/dev/null)
                        if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                            instance_dir=$(dirname "$pid_file")
                            instance_name=$(basename "$instance_dir")
                            echo "  ${CYAN}$instance_name${NC}"
                            echo "    PID: $pid"
                            echo "    State: $instance_dir"
                            if [ -f "$instance_dir/qemu.log" ]; then
                                # Try to extract port forwards from qemu command line
                                ports=$(grep -o 'hostfwd=[^,]*' "$instance_dir/qemu.log" 2>/dev/null | sed 's/hostfwd=tcp:://g; s/-/:/' | tr '\n' ' ')
                                [ -n "$ports" ] && echo "    Ports: $ports"
                            fi
                            echo ""
                            found=$((found + 1))
                            tracked_pids="$tracked_pids $pid"
                        fi
                    done
                    if [ $found -eq 0 ]; then
                        echo "  (none)"
                    fi

                    # Check for zombie/orphan QEMU processes (vdkr or vpdmn)
                    echo ""
                    echo "Checking for orphan QEMU processes..."
                    zombies=""
                    for qemu_pid in $(pgrep -f "qemu-system.*runtime=(docker|podman)" 2>/dev/null || true); do
                        # Skip if this PID is already tracked
                        if echo "$tracked_pids" | grep -qw "$qemu_pid"; then
                            continue
                        fi
                        # Also check other tool's state dirs
                        other_tracked=false
                        for vpid_file in "$OTHER_STATE_DIR"/*/daemon.pid; do
                            [ -f "$vpid_file" ] || continue
                            vpid=$(cat "$vpid_file" 2>/dev/null)
                            if [ "$vpid" = "$qemu_pid" ]; then
                                other_tracked=true
                                break
                            fi
                        done
                        if [ "$other_tracked" = "true" ]; then
                            continue
                        fi
                        zombies="$zombies $qemu_pid"
                    done

                    if [ -n "$zombies" ]; then
                        echo ""
                        echo -e "${YELLOW}Orphan QEMU processes found:${NC}"
                        for zpid in $zombies; do
                            # Extract runtime from cmdline
                            cmdline=$(cat /proc/$zpid/cmdline 2>/dev/null | tr '\0' ' ')
                            runtime=$(echo "$cmdline" | grep -o 'runtime=[a-z]*' | cut -d= -f2)
                            state_dir=$(echo "$cmdline" | grep -o 'path=[^,]*daemon.sock' | sed 's|path=||; s|/daemon.sock||')
                            echo ""
                            echo "  ${RED}PID $zpid${NC} (${runtime:-unknown})"
                            [ -n "$state_dir" ] && echo "    State: $state_dir"
                            echo "    Kill with: kill $zpid"
                        done
                        echo ""
                        echo -e "To kill all orphans: ${CYAN}kill$zombies${NC}"
                    else
                        echo "  (no orphans found)"
                    fi
                fi
                ;;
            clean-ports)
                # Clear the port forward registry without stopping daemon
                pf_file=$(get_port_forward_file)
                if [ -f "$pf_file" ]; then
                    count=$(wc -l < "$pf_file")
                    rm -f "$pf_file"
                    echo -e "${GREEN}[$VCONTAINER_RUNTIME_NAME]${NC} Cleared $count port forward entries from registry"
                else
                    echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Port forward registry is already empty"
                fi
                ;;
            *)
                echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Unknown memres subcommand: $MEMRES_CMD" >&2
                echo "Usage: $VCONTAINER_RUNTIME_NAME vmemres start|stop|restart|status|list|clean-ports" >&2
                exit 1
                ;;
        esac
        ;;

    bundle)
        # Create an OCI runtime bundle from a container image.
        # Usage: <tool> bundle <image> <output-dir> [-- <cmd> ...]
        #
        # Pulls the image via skopeo, extracts layers into rootfs/,
        # and generates config.json from the OCI image config.
        # Optional command after -- overrides the image's default entrypoint.
        # The resulting bundle can be passed to vxn-oci-runtime create --bundle.
        [ "${VCONTAINER_HYPERVISOR:-}" = "xen" ] || {
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} bundle is only supported for Xen (vxn)" >&2
            exit 1
        }

        if [ ${#COMMAND_ARGS[@]} -lt 2 ]; then
            echo "Usage: $VCONTAINER_RUNTIME_NAME bundle <image> <output-dir> [-- <cmd> ...]" >&2
            echo "" >&2
            echo "Creates an OCI runtime bundle from a container image." >&2
            echo "The bundle can then be used with vxn-oci-runtime:" >&2
            echo "" >&2
            echo "  $VCONTAINER_RUNTIME_NAME bundle alpine /tmp/test-bundle -- /bin/echo hello" >&2
            echo "  vxn-oci-runtime create --bundle /tmp/test-bundle --pid-file /tmp/t.pid test1" >&2
            echo "  vxn-oci-runtime start test1" >&2
            echo "  vxn-oci-runtime state test1" >&2
            echo "  vxn-oci-runtime delete test1" >&2
            exit 1
        fi

        BUNDLE_IMAGE="${COMMAND_ARGS[0]}"
        BUNDLE_DIR="${COMMAND_ARGS[1]}"

        # Parse optional command override after --
        BUNDLE_CMD_OVERRIDE=()
        _bundle_found_sep=false
        for _ba in "${COMMAND_ARGS[@]:2}"; do
            if [ "$_bundle_found_sep" = "true" ]; then
                BUNDLE_CMD_OVERRIDE+=("$_ba")
            elif [ "$_ba" = "--" ]; then
                _bundle_found_sep=true
            fi
        done

        # Check prerequisites
        command -v skopeo >/dev/null 2>&1 || {
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} skopeo not found (needed for image pull)" >&2
            exit 1
        }
        command -v jq >/dev/null 2>&1 || {
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} jq not found (needed for OCI config parsing)" >&2
            exit 1
        }

        # Pull image via skopeo
        BUNDLE_TMP=$(mktemp -d)
        trap 'rm -rf "$BUNDLE_TMP"' EXIT
        BUNDLE_OCI="$BUNDLE_TMP/oci"

        echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Pulling $BUNDLE_IMAGE..."
        if ! skopeo copy "docker://$BUNDLE_IMAGE" "oci:$BUNDLE_OCI:latest" 2>&1; then
            echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Failed to pull image: $BUNDLE_IMAGE" >&2
            exit 1
        fi

        # Extract layers into rootfs/
        mkdir -p "$BUNDLE_DIR/rootfs"

        BUNDLE_MANIFEST_DIGEST=$(jq -r '.manifests[0].digest' "$BUNDLE_OCI/index.json")
        BUNDLE_MANIFEST="$BUNDLE_OCI/blobs/${BUNDLE_MANIFEST_DIGEST/://}"
        BUNDLE_CONFIG_DIGEST=$(jq -r '.config.digest' "$BUNDLE_MANIFEST")
        BUNDLE_CONFIG="$BUNDLE_OCI/blobs/${BUNDLE_CONFIG_DIGEST/://}"

        echo -e "${CYAN}[$VCONTAINER_RUNTIME_NAME]${NC} Extracting layers..."
        for layer_digest in $(jq -r '.layers[].digest' "$BUNDLE_MANIFEST"); do
            layer_file="$BUNDLE_OCI/blobs/${layer_digest/://}"
            [ -f "$layer_file" ] && tar -xf "$layer_file" -C "$BUNDLE_DIR/rootfs" 2>/dev/null || true
        done

        # Parse OCI config
        BUNDLE_ENTRYPOINT=$(jq -r '(.config.Entrypoint // [])' "$BUNDLE_CONFIG")
        BUNDLE_CMD=$(jq -r '(.config.Cmd // [])' "$BUNDLE_CONFIG")
        BUNDLE_ENV=$(jq -r '(.config.Env // [])' "$BUNDLE_CONFIG")
        BUNDLE_CWD=$(jq -r '.config.WorkingDir // "/"' "$BUNDLE_CONFIG")
        [ -z "$BUNDLE_CWD" ] && BUNDLE_CWD="/"

        # Merge Entrypoint + Cmd into process.args (or use override)
        if [ ${#BUNDLE_CMD_OVERRIDE[@]} -gt 0 ]; then
            BUNDLE_ARGS=$(printf '%s\n' "${BUNDLE_CMD_OVERRIDE[@]}" | jq -R . | jq -s .)
        else
            BUNDLE_ARGS=$(jq -n \
                --argjson ep "$BUNDLE_ENTRYPOINT" \
                --argjson cmd "$BUNDLE_CMD" \
                '$ep + $cmd')
        fi

        # Generate config.json
        jq -n \
            --argjson args "$BUNDLE_ARGS" \
            --argjson env "$BUNDLE_ENV" \
            --arg cwd "$BUNDLE_CWD" \
        '{
            ociVersion: "1.0.2",
            process: {
                args: $args,
                env: $env,
                cwd: $cwd
            },
            root: { path: "rootfs" }
        }' > "$BUNDLE_DIR/config.json"

        rm -rf "$BUNDLE_TMP"
        trap - EXIT

        BUNDLE_ARGS_DISPLAY=$(jq -r 'join(" ")' <<< "$BUNDLE_ARGS")
        echo -e "${GREEN}[$VCONTAINER_RUNTIME_NAME]${NC} Bundle created: $BUNDLE_DIR"
        echo -e "  entrypoint: $BUNDLE_ARGS_DISPLAY"
        echo -e "  cwd: $BUNDLE_CWD"
        ;;

    *)
        echo -e "${RED}[$VCONTAINER_RUNTIME_NAME]${NC} Unknown command: $COMMAND" >&2
        echo "Run '$VCONTAINER_RUNTIME_NAME --help' for usage" >&2
        exit 1
        ;;
esac
