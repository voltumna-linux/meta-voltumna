#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vdkr-init.sh
# Init script for vdkr: execute arbitrary docker commands in QEMU
#
# This script runs on a real ext4 filesystem after switch_root from initramfs.
# The preinit script mounted /dev/vda (rootfs.img) and did switch_root to us.
#
# Drive layout (rootfs.img is always /dev/vda, mounted as /):
#   /dev/vda = rootfs.img (this script runs from here, mounted as /)
#   /dev/vdb = input disk (optional, OCI/tar/dir data)
#   /dev/vdc = state disk (optional, persistent Docker storage)
#
# Kernel parameters:
#   docker_cmd=<base64>    Base64-encoded docker command + args
#   docker_input=<type>    Input type: none, oci, tar, dir (default: none)
#   docker_output=<type>   Output type: text, tar, storage (default: text)
#   docker_state=<type>    State type: none, disk (default: none)
#   docker_network=1       Enable networking (configure eth0, DNS)
#   docker_registry=<url>  Default registry for unqualified images (e.g., 10.0.2.2:5000/yocto)
#   docker_insecure_registry=<host:port>  Mark registry as insecure (HTTP). Can repeat.
#   docker_registry_secure=1              Enable TLS verification for registry
#   docker_registry_ca=1                  CA certificate available in /mnt/share/ca.crt
#   docker_registry_user=<user>           Registry username for authentication
#   docker_registry_pass=<base64>         Base64-encoded registry password
#   docker_auth=1                         A pre-built docker config.json is available
#                                         on a dedicated read-only 9p share tagged
#                                         "vdkr_auth" (mounted at /mnt/auth). Takes
#                                         precedence over docker_registry_user/pass.
#
# Version: 2.5.0

# Set runtime-specific parameters before sourcing common code
VCONTAINER_RUNTIME_NAME="vdkr"
VCONTAINER_RUNTIME_CMD="docker"
VCONTAINER_RUNTIME_PREFIX="docker"
VCONTAINER_STATE_DIR="/var/lib/docker"
VCONTAINER_SHARE_NAME="vdkr_share"
VCONTAINER_VERSION="2.5.0"

# Docker-specific: default registry for unqualified image names
# Set via kernel param: docker_registry=10.0.2.2:5000/yocto
# Or baked into rootfs: /etc/vdkr/registry.conf
DOCKER_DEFAULT_REGISTRY=""

# Secure registry mode (TLS verification)
# Set via kernel param: docker_registry_secure=1
# CA cert passed via: virtio-9p share at /mnt/share/ca.crt
DOCKER_REGISTRY_SECURE=""
DOCKER_REGISTRY_CA=""
DOCKER_REGISTRY_USER=""
DOCKER_REGISTRY_PASS=""

# Source common init functions
# When installed as /init, common file is at /vcontainer-init-common.sh
. /vcontainer-init-common.sh

# Load baked-in registry defaults from /etc/vdkr/registry.conf
# These can be overridden by kernel cmdline parameters
load_registry_config() {
    if [ -f /etc/vdkr/registry.conf ]; then
        . /etc/vdkr/registry.conf
        # Map config file variables to our internal variables
        if [ -n "$VDKR_DEFAULT_REGISTRY" ]; then
            DOCKER_DEFAULT_REGISTRY="$VDKR_DEFAULT_REGISTRY"
            log "Loaded baked registry: $DOCKER_DEFAULT_REGISTRY"
        fi
        # VDKR_INSECURE_REGISTRIES is handled in start_dockerd
    fi
}

# Parse secure registry settings from kernel cmdline
parse_secure_registry_config() {
    # Check for secure mode flag
    GREP_RESULT=$(grep -o 'docker_registry_secure=[^ ]*' /proc/cmdline 2>/dev/null || true)
    if [ -n "$GREP_RESULT" ]; then
        DOCKER_REGISTRY_SECURE=$(echo "$GREP_RESULT" | sed 's/docker_registry_secure=//')
        log "Secure registry mode: $DOCKER_REGISTRY_SECURE"
    fi

    # Check for CA certificate in shared folder (passed via virtio-9p)
    if [ -f "/mnt/share/ca.crt" ]; then
        DOCKER_REGISTRY_CA="/mnt/share/ca.crt"
        log "Found CA certificate in shared folder"
    fi

    # Check for registry user
    GREP_RESULT=$(grep -o 'docker_registry_user=[^ ]*' /proc/cmdline 2>/dev/null || true)
    if [ -n "$GREP_RESULT" ]; then
        DOCKER_REGISTRY_USER=$(echo "$GREP_RESULT" | sed 's/docker_registry_user=//')
        log "Registry user: $DOCKER_REGISTRY_USER"
    fi

    # Check for registry password (base64 encoded)
    GREP_RESULT=$(grep -o 'docker_registry_pass=[^ ]*' /proc/cmdline 2>/dev/null || true)
    if [ -n "$GREP_RESULT" ]; then
        DOCKER_REGISTRY_PASS=$(echo "$GREP_RESULT" | sed 's/docker_registry_pass=//')
        log "Received registry password from cmdline"
    fi
}

# Install CA certificate for secure registry
# Creates /etc/docker/certs.d/{registry}/ca.crt
install_registry_ca() {
    if [ "$DOCKER_REGISTRY_SECURE" != "1" ]; then
        return 0
    fi

    if [ -z "$DOCKER_DEFAULT_REGISTRY" ]; then
        log "WARNING: Secure mode enabled but no registry configured"
        return 0
    fi

    # Extract registry host (strip path/namespace)
    local registry_host=$(echo "$DOCKER_DEFAULT_REGISTRY" | cut -d'/' -f1)

    # Install CA cert if provided via shared folder
    if [ -n "$DOCKER_REGISTRY_CA" ] && [ -f "$DOCKER_REGISTRY_CA" ]; then
        local cert_dir="/etc/docker/certs.d/$registry_host"
        mkdir -p "$cert_dir"

        # Copy CA cert from shared folder
        if cp "$DOCKER_REGISTRY_CA" "$cert_dir/ca.crt" 2>/dev/null && [ -s "$cert_dir/ca.crt" ]; then
            log "Installed CA certificate: $cert_dir/ca.crt"
        else
            log "WARNING: Failed to copy CA certificate from $DOCKER_REGISTRY_CA"
            rm -f "$cert_dir/ca.crt"
        fi
    else
        # Check if CA cert exists from baked rootfs
        local cert_dir="/etc/docker/certs.d/$registry_host"
        if [ -f "$cert_dir/ca.crt" ]; then
            log "Using baked CA certificate: $cert_dir/ca.crt"
        else
            log "WARNING: Secure mode enabled but no CA certificate available"
        fi
    fi

    # Setup Docker auth if credentials provided
    if [ -n "$DOCKER_REGISTRY_USER" ] && [ -n "$DOCKER_REGISTRY_PASS" ]; then
        local password=$(echo "$DOCKER_REGISTRY_PASS" | base64 -d 2>/dev/null)
        if [ -n "$password" ]; then
            mkdir -p /root/.docker
            # Create auth config
            local auth=$(echo -n "$DOCKER_REGISTRY_USER:$password" | base64 | tr -d '\n')
            cat > /root/.docker/config.json << EOF
{
  "auths": {
    "$registry_host": {
      "auth": "$auth"
    }
  }
}
EOF
            chmod 600 /root/.docker/config.json
            log "Configured Docker auth for: $registry_host"
        else
            log "WARNING: Failed to decode registry password"
        fi
    fi
}

# Install a user-supplied docker config.json from the dedicated read-only
# auth 9p share (mounted at /mnt/auth by mount_auth_share). This takes
# precedence over credentials supplied via docker_registry_user/pass.
#
# Security posture:
#   * File is read from a read-only 9p share with a separate tag ("vdkr_auth")
#     so it cannot leak into /mnt/share outputs.
#   * Target is written with mode 0600 and the parent dir with mode 0700.
#   * We unmount /mnt/auth immediately after copying so neither the dockerd
#     runtime nor user workloads in the VM have an open reference to the
#     host-side staging directory.
install_auth_config() {
    if [ "$RUNTIME_AUTH" != "1" ]; then
        return 0
    fi

    if ! mount_auth_share; then
        log "WARNING: docker_auth=1 was set but the auth 9p share did not mount"
        return 1
    fi

    local src="$AUTH_SHARE_MOUNT/config.json"
    if [ ! -f "$src" ]; then
        log "WARNING: expected $src on auth share but file is missing"
        unmount_auth_share
        return 1
    fi

    mkdir -p /root/.docker
    chmod 700 /root/.docker

    if cp "$src" /root/.docker/config.json 2>/dev/null; then
        chmod 600 /root/.docker/config.json
        log "Installed registry auth config at /root/.docker/config.json"
        if [ -n "$DOCKER_REGISTRY_USER" ] || [ -n "$DOCKER_REGISTRY_PASS" ]; then
            log "NOTE: --config takes precedence over --registry-user/--registry-pass"
        fi
    else
        log "ERROR: failed to copy auth config to /root/.docker/config.json"
        unmount_auth_share
        return 1
    fi

    # Release the host-side share so credentials aren't still addressable
    # through /mnt/auth for the lifetime of the VM.
    unmount_auth_share
    return 0
}

# ============================================================================
# Docker-Specific Functions
# ============================================================================

setup_docker_storage() {
    mkdir -p /run/containerd /run/lock
    mkdir -p /var/lib/docker
    mkdir -p /var/lib/containerd

    # Handle Docker storage
    if [ -n "$STATE_DISK" ] && [ -b "$STATE_DISK" ]; then
        log "Mounting state disk $STATE_DISK as /var/lib/docker..."
        if mount -t ext4 "$STATE_DISK" /var/lib/docker 2>&1; then
            log "SUCCESS: Mounted $STATE_DISK as Docker storage"
            log "Docker storage contents:"
            [ "$QUIET_BOOT" = "0" ] && ls -la /var/lib/docker/ 2>/dev/null || log "(empty)"
        else
            log "WARNING: Failed to mount state disk, using tmpfs"
            RUNTIME_STATE="none"
        fi
    fi

    # If no state disk, use tmpfs for Docker storage
    if [ "$RUNTIME_STATE" != "disk" ]; then
        log "Using tmpfs for Docker storage (ephemeral)..."
        mount -t tmpfs -o size=1G tmpfs /var/lib/docker
    fi
}

start_containerd() {
    CONTAINERD_READY=false
    if [ -x "/usr/bin/containerd" ]; then
        log "Starting containerd..."
        mkdir -p /var/lib/containerd
        mkdir -p /run/containerd
        /usr/bin/containerd --log-level info --root /var/lib/containerd --state /run/containerd >/tmp/containerd.log 2>&1 &
        CONTAINERD_PID=$!
        # Wait for containerd socket
        for i in 1 2 3 4 5 6 7 8 9 10; do
            if [ -S /run/containerd/containerd.sock ]; then
                log "Containerd running (PID: $CONTAINERD_PID)"
                CONTAINERD_READY=true
                break
            fi
            sleep 1
        done
        if [ "$CONTAINERD_READY" != "true" ]; then
            log "WARNING: Containerd failed to start, check /tmp/containerd.log"
            [ -f /tmp/containerd.log ] && cat /tmp/containerd.log >&2
        fi
    fi
}

start_dockerd() {
    log "Starting Docker daemon..."
    DOCKER_OPTS="--data-root=/var/lib/docker"
    DOCKER_OPTS="$DOCKER_OPTS --storage-driver=overlay2"
    # Enable iptables for Docker bridge NAT and port forwarding
    DOCKER_OPTS="$DOCKER_OPTS --iptables=true"
    DOCKER_OPTS="$DOCKER_OPTS --userland-proxy=false"
    # Use default docker0 bridge (172.17.0.0/16) for container networking
    DOCKER_OPTS="$DOCKER_OPTS --host=unix:///var/run/docker.sock"
    DOCKER_OPTS="$DOCKER_OPTS --exec-opt native.cgroupdriver=cgroupfs"
    DOCKER_OPTS="$DOCKER_OPTS --log-level=info"

    # Parse default registry from kernel cmdline (docker_registry=host:port/namespace)
    # Kernel cmdline OVERRIDES baked config from /etc/vdkr/registry.conf
    # Use docker_registry=none to explicitly disable baked registry
    # This enables: "docker pull container-base" → "docker pull 10.0.2.2:5000/yocto/container-base"
    GREP_RESULT=$(grep -o 'docker_registry=[^ ]*' /proc/cmdline 2>/dev/null || true)
    if [ -n "$GREP_RESULT" ]; then
        CMDLINE_REGISTRY=$(echo "$GREP_RESULT" | sed 's/docker_registry=//')
        if [ "$CMDLINE_REGISTRY" = "none" ] || [ -z "$CMDLINE_REGISTRY" ]; then
            DOCKER_DEFAULT_REGISTRY=""
            log "Registry disabled via cmdline"
        else
            DOCKER_DEFAULT_REGISTRY="$CMDLINE_REGISTRY"
            log "Registry from cmdline: $DOCKER_DEFAULT_REGISTRY"
        fi
    elif [ -n "$DOCKER_DEFAULT_REGISTRY" ]; then
        log "Registry from baked config: $DOCKER_DEFAULT_REGISTRY"
    fi
    if [ -n "$DOCKER_DEFAULT_REGISTRY" ]; then
        # Extract host:port for insecure registry config (strip path/namespace)
        REGISTRY_HOST=$(echo "$DOCKER_DEFAULT_REGISTRY" | cut -d'/' -f1)

        # In secure mode, DO NOT add to insecure-registries (use TLS verification)
        if [ "$DOCKER_REGISTRY_SECURE" = "1" ]; then
            log "Secure mode: using TLS verification for $REGISTRY_HOST"
        else
            # Auto-add to insecure registries if it looks like a local/private registry
            if echo "$REGISTRY_HOST" | grep -qE '^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'; then
                DOCKER_OPTS="$DOCKER_OPTS --insecure-registry=$REGISTRY_HOST"
                log "Auto-added insecure registry: $REGISTRY_HOST"
            fi
        fi
    fi

    # Add baked insecure registries from /etc/vdkr/registry.conf
    if [ -n "$VDKR_INSECURE_REGISTRIES" ]; then
        for registry in $VDKR_INSECURE_REGISTRIES; do
            DOCKER_OPTS="$DOCKER_OPTS --insecure-registry=$registry"
            log "Added baked insecure registry: $registry"
        done
    fi

    # Check for additional insecure registries from kernel cmdline (docker_insecure_registry=host:port)
    # For local registry on build host via QEMU slirp: docker_insecure_registry=10.0.2.2:5000
    # For remote HTTP registry: docker_insecure_registry=registry.company.com:5000
    # Multiple registries can be specified by repeating the parameter
    for registry in $(grep -o 'docker_insecure_registry=[^ ]*' /proc/cmdline 2>/dev/null | sed 's/docker_insecure_registry=//' || true); do
        if [ -n "$registry" ]; then
            DOCKER_OPTS="$DOCKER_OPTS --insecure-registry=$registry"
            log "Added insecure registry: $registry"
        fi
    done

    if [ "$CONTAINERD_READY" = "true" ]; then
        DOCKER_OPTS="$DOCKER_OPTS --containerd=/run/containerd/containerd.sock"
    fi

    /usr/bin/dockerd $DOCKER_OPTS >/var/log/docker.log 2>&1 &
    DOCKER_PID=$!
    log "Docker daemon started (PID: $DOCKER_PID)"

    # Wait for Docker to be ready
    log "Waiting for Docker daemon..."
    DOCKER_READY=false

    sleep 5

    for i in $(seq 1 60); do
        if ! kill -0 $DOCKER_PID 2>/dev/null; then
            echo "===ERROR==="
            echo "Docker daemon died after $i iterations"
            echo "Docker log:"
            cat /var/log/docker.log 2>/dev/null || true
            dmesg | tail -20 2>/dev/null || true
            sleep 2
            reboot -f
        fi

        # Try docker info and capture any error
        DOCKER_INFO_OUT=$(/usr/bin/docker info 2>&1)
        DOCKER_INFO_RC=$?
        if [ $DOCKER_INFO_RC -eq 0 ]; then
            log "Docker daemon is ready!"
            DOCKER_READY=true
            break
        fi

        log "Waiting... ($i/60) - docker info rc=$DOCKER_INFO_RC"
        # Show first line of error on every 10th iteration
        if [ $((i % 10)) -eq 0 ]; then
            echo "docker info error: $(echo "$DOCKER_INFO_OUT" | head -1)"
        fi
        sleep 2
    done

    if [ "$DOCKER_READY" != "true" ]; then
        echo "===ERROR==="
        echo "Docker failed to start after 60 attempts"
        echo "Last docker info output:"
        echo "$DOCKER_INFO_OUT" | head -5
        echo "Docker log tail:"
        tail -20 /var/log/docker.log 2>/dev/null || true
        sleep 5
        reboot -f
    fi
}

stop_runtime_daemons() {
    # Stop Docker daemon
    if [ -n "$DOCKER_PID" ]; then
        log "Stopping Docker daemon..."
        kill $DOCKER_PID 2>/dev/null || true
        for i in $(seq 1 10); do
            if ! kill -0 $DOCKER_PID 2>/dev/null; then
                log "Docker daemon stopped"
                break
            fi
            sleep 1
        done
    fi

    # Stop containerd
    if [ -n "$CONTAINERD_PID" ]; then
        log "Stopping containerd..."
        kill $CONTAINERD_PID 2>/dev/null || true
        sleep 2
    fi
}

# Execute a pull command with registry fallback
# Tries registry first, falls back to Docker Hub if image not found
# Usage: execute_pull_with_fallback "docker pull alpine:latest"
# Returns: exit code of successful pull, or last failure
execute_pull_with_fallback() {
    local cmd="$1"
    local image=""
    local tag=""

    # Extract image name from pull command
    # Handles: docker pull <image> or docker pull <image>:tag
    if echo "$cmd" | grep -qE '^docker pull '; then
        image=$(echo "$cmd" | awk '{print $3}')
    else
        # Not a pull command, just execute it
        eval "$cmd"
        return $?
    fi

    # If no registry configured, just run the original command
    if [ -z "$DOCKER_DEFAULT_REGISTRY" ]; then
        log "No registry configured, pulling from Docker Hub"
        eval "$cmd"
        return $?
    fi

    # Check if image is already qualified (has / in it)
    if echo "$image" | grep -q '/'; then
        # Already qualified (e.g., docker.io/library/alpine or myregistry/image)
        log "Image already qualified: $image"
        eval "$cmd"
        return $?
    fi

    # Unqualified image - try registry first, then Docker Hub
    local registry_image="$DOCKER_DEFAULT_REGISTRY/$image"

    log "Trying registry first: $registry_image"
    if docker pull "$registry_image" 2>/dev/null; then
        log "Successfully pulled from registry: $registry_image"
        docker images | grep -E "REPOSITORY|$image" || true
        return 0
    fi

    log "Image not in registry, falling back to Docker Hub: $image"
    if docker pull "$image"; then
        log "Successfully pulled from Docker Hub: $image"
        docker images | grep -E "REPOSITORY|$image" || true
        return 0
    fi

    log "ERROR: Failed to pull $image from both registry and Docker Hub"
    return 1
}

# Check if a command is a pull command that needs fallback handling
is_pull_command() {
    local cmd="$1"
    echo "$cmd" | grep -qE '^docker pull '
}

# Helper function to check if an image exists locally
# Returns 0 if exists, 1 if not
image_exists_locally() {
    local img="$1"
    # Try exact match first, then with :latest suffix
    if docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -qE "^${img}$"; then
        return 0
    fi
    # If no tag specified, try with :latest
    if ! echo "$img" | grep -q ':'; then
        if docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -qE "^${img}:latest$"; then
            return 0
        fi
    fi
    return 1
}

# Helper function to transform an unqualified image name
# Must be defined before transform_docker_command which uses it
# Priority: 1) local image as-is, 2) with registry prefix, 3) unchanged
transform_image_name() {
    local img="$1"
    if [ -z "$img" ]; then
        echo ""
        return
    fi
    # Check if this is an image ID (hex string) - don't transform
    # Short form: 12 hex chars (e7b39c54cdec)
    # Long form: sha256:64 hex chars
    if echo "$img" | grep -qE '^[0-9a-fA-F]{12,64}$'; then
        echo "$img"
        return
    fi
    if echo "$img" | grep -qE '^sha256:[0-9a-fA-F]{64}$'; then
        echo "$img"
        return
    fi
    # Check if image is unqualified (no /)
    if ! echo "$img" | grep -q '/'; then
        # First check if image exists locally as-is
        if image_exists_locally "$img"; then
            echo "$img"
            return
        fi
        # If not local and we have a default registry, use it
        if [ -n "$DOCKER_DEFAULT_REGISTRY" ]; then
            echo "$DOCKER_DEFAULT_REGISTRY/$img"
            return
        fi
        # No registry configured, use as-is (Docker will try Docker Hub)
        echo "$img"
    # Check if already has registry with port - don't transform
    elif echo "$img" | grep -qE '^[^/]+:[0-9]+/'; then
        echo "$img"
    # Check if looks like a domain - don't transform
    elif echo "$img" | grep -qE '^[a-zA-Z0-9-]+\.[a-zA-Z]'; then
        echo "$img"
    else
        echo "$img"
    fi
}

# Transform docker commands to use default registry for unqualified images
# "docker pull container-base" → "docker pull 10.0.2.2:5000/yocto/container-base"
# "docker pull alpine" → "docker pull 10.0.2.2:5000/yocto/alpine" (if registry set)
# "docker pull docker.io/library/alpine" → unchanged (already qualified)
# Also handles "docker image *" compound commands and other image commands
#
# NOTE: Pull commands are NOT transformed here - they use execute_pull_with_fallback
# which tries registry first, then Docker Hub as fallback.
transform_docker_command() {
    local cmd="$1"

    # Handle "docker image *" compound commands - convert to standard form
    # docker image pull → docker pull
    # docker image rm → docker rmi
    # docker image ls → docker images
    # docker image inspect → docker inspect (works for images)
    if echo "$cmd" | grep -qE '^docker image '; then
        local subcmd=$(echo "$cmd" | awk '{print $3}')
        local rest=$(echo "$cmd" | cut -d' ' -f4-)
        case "$subcmd" in
            pull)    cmd="docker pull $rest" ;;
            rm)      cmd="docker rmi $rest" ;;
            ls)      cmd="docker images $rest" ;;
            inspect) cmd="docker inspect $rest" ;;
            tag)     cmd="docker tag $rest" ;;
            push)    cmd="docker push $rest" ;;
            prune)   cmd="docker image prune $rest" ;;  # keep as-is, docker supports it
            history) cmd="docker history $rest" ;;
            *)       ;;  # pass through unknown subcommands
        esac
    fi

    # Only transform if default registry is configured
    if [ -z "$DOCKER_DEFAULT_REGISTRY" ]; then
        echo "$cmd"
        return
    fi

    # NOTE: docker images, inspect, history, rmi, tag do NOT get transformed.
    # These commands operate on local images - the user specifies exactly what they have.
    # Transform only applies to pull/run where we're fetching images.
    #
    # If user has:
    #   - alpine:latest (from Docker Hub via fallback)
    #   - 10.0.2.2:5000/yocto/myapp:latest (from registry)
    #
    # Then:
    #   - "docker images alpine" → shows alpine:latest (no transform)
    #   - "docker inspect alpine" → inspects alpine:latest (no transform)
    #   - "docker rmi alpine" → removes alpine:latest (no transform)

    # Pull commands are handled by execute_pull_with_fallback, not transformed here
    if echo "$cmd" | grep -qE '^docker pull '; then
        echo "$cmd"
        return
    fi

    # Check if this is a run command
    if echo "$cmd" | grep -qE '^docker run '; then
        # Extract the image reference (handles "docker run [opts] img [cmd]")
        local docker_cmd="run"
        local rest=""

        if [ "$docker_cmd" = "run" ]; then
            # docker run [options] <image> [command]
            # This is trickier - image is the first non-option argument
            # For simplicity, look for image pattern after run
            # Skip known options that take arguments
            local args=$(echo "$cmd" | cut -d' ' -f3-)
            local image=""
            local new_args=""
            local skip_next=false

            for arg in $args; do
                # Once we have the image, everything else is the container command
                if [ -n "$image" ]; then
                    rest="$rest $arg"
                    continue
                fi

                if [ "$skip_next" = "true" ]; then
                    new_args="$new_args $arg"
                    skip_next=false
                    continue
                fi

                case "$arg" in
                    -d|--detach|-i|--interactive|-t|--tty|--rm|--privileged)
                        new_args="$new_args $arg"
                        ;;
                    -p|--publish|-v|--volume|-e|--env|--name|--network|-w|--workdir|--entrypoint|-m|--memory|--cpus|--cpu-shares)
                        new_args="$new_args $arg"
                        skip_next=true
                        ;;
                    -p=*|--publish=*|-v=*|--volume=*|-e=*|--env=*|--name=*|--network=*|-w=*|--workdir=*|--entrypoint=*|-m=*|--memory=*)
                        new_args="$new_args $arg"
                        ;;
                    -*)
                        # Other options, pass through
                        new_args="$new_args $arg"
                        ;;
                    *)
                        # First non-option is the image
                        image="$arg"
                        ;;
                esac
            done

            if [ -n "$image" ]; then
                local transformed=$(transform_image_name "$image")
                echo "docker run$new_args $transformed$rest"
                return
            fi
        fi
    fi

    # Return unchanged
    echo "$cmd"
}

handle_storage_output() {
    echo "Stopping Docker gracefully..."
    /usr/bin/docker system prune -f >/dev/null 2>&1 || true
    kill $DOCKER_PID 2>/dev/null || true
    [ -n "$CONTAINERD_PID" ] && kill $CONTAINERD_PID 2>/dev/null || true
    sleep 3

    echo "Packaging Docker storage..."
    cd /var/lib
    tar -cf /tmp/storage.tar docker/

    STORAGE_SIZE=$(stat -c%s /tmp/storage.tar 2>/dev/null || echo "0")
    echo "Storage size: $STORAGE_SIZE bytes"

    if [ "$STORAGE_SIZE" -gt 1000 ]; then
        # Use virtio-9p if available (much faster than console base64)
        if [ "$RUNTIME_9P" = "1" ] && mountpoint -q /mnt/share 2>/dev/null; then
            echo "Using virtio-9p for storage output (fast path)"
            cp /tmp/storage.tar /mnt/share/storage.tar
            sync
            echo "===9P_STORAGE_DONE==="
            echo "===EXIT_CODE=$EXEC_EXIT_CODE==="
        else
            # Fallback: base64 to console (slow)
            dmesg -n 1
            echo "===STORAGE_START==="
            base64 /tmp/storage.tar
            echo "===STORAGE_END==="
            echo "===EXIT_CODE=$EXEC_EXIT_CODE==="
        fi
    else
        echo "===ERROR==="
        echo "Storage too small"
    fi
}

# ============================================================================
# Main
# ============================================================================

# Initialize base environment
setup_base_environment
mount_base_filesystems

# Check for quiet boot mode
check_quiet_boot

log "=== vdkr Init ==="
log "Version: $VCONTAINER_VERSION"

# Mount tmpfs directories and cgroups
mount_tmpfs_dirs
setup_cgroups

# Parse kernel command line
parse_cmdline

# Mount 9p share if available (for fast storage output in batch-import mode)
if [ "$RUNTIME_9P" = "1" ]; then
    mkdir -p /mnt/share
    if mount -t 9p -o trans=${NINE_P_TRANSPORT},version=9p2000.L,cache=none ${VCONTAINER_SHARE_NAME} /mnt/share 2>/dev/null; then
        log "Mounted 9p share at /mnt/share (transport: ${NINE_P_TRANSPORT})"
    else
        log "WARNING: Could not mount 9p share, falling back to console output"
        RUNTIME_9P="0"
    fi
fi

# Detect and configure disks
detect_disks

# Set up Docker storage (Docker-specific)
setup_docker_storage

# Mount input disk
mount_input_disk

# Configure networking
configure_networking

# Load baked registry config (can be overridden by kernel cmdline)
load_registry_config

# Parse secure registry settings from kernel cmdline
parse_secure_registry_config

# Install CA certificate for secure registry
install_registry_ca

# Install user-supplied docker config.json from the dedicated auth 9p share.
# Must run AFTER install_registry_ca so that --config takes precedence when
# both mechanisms are used.
install_auth_config

# Start containerd and dockerd (Docker-specific)
start_containerd
start_dockerd

# Handle daemon mode or single command execution
if [ "$RUNTIME_DAEMON" = "1" ]; then
    # Export registry for daemon mode
    # Note: Functions (execute_pull_with_fallback, is_pull_command) are already
    # available since they're defined in this script before run_daemon_mode is called
    export DOCKER_DEFAULT_REGISTRY
    run_daemon_mode
else
    prepare_input_path
    # Check if this is a pull command - use fallback logic
    if is_pull_command "$RUNTIME_CMD"; then
        # Pull commands use registry-first, Docker Hub fallback
        log "Using pull with registry fallback"
        execute_pull_with_fallback "$RUNTIME_CMD"
        EXEC_EXIT_CODE=$?
        echo "===EXIT_CODE=$EXEC_EXIT_CODE==="
        graceful_shutdown
        exit 0
    fi
    # Transform other commands to use default registry for unqualified images
    if [ -n "$DOCKER_DEFAULT_REGISTRY" ]; then
        RUNTIME_CMD=$(transform_docker_command "$RUNTIME_CMD")
    fi
    execute_command
fi

# Graceful shutdown
graceful_shutdown
