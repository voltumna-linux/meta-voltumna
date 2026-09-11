#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vrunner-backend-xen.sh
# Xen hypervisor backend for vrunner.sh
#
# This backend implements the hypervisor interface for Xen xl toolstack.
# It is sourced by vrunner.sh when VCONTAINER_HYPERVISOR=xen.
#
# This backend runs on a Xen Dom0 host and creates DomU guests using xl.
# Key differences from QEMU backend:
#   - Block devices appear as /dev/xvd* instead of /dev/vd*
#   - Network uses bridge + iptables NAT instead of QEMU slirp
#   - Console uses PV console (hvc0) with serial='pty' for PTY on Dom0
#   - Daemon IPC uses direct PTY I/O (no socat bridge needed)
#   - VM tracking uses domain name instead of PID

# ============================================================================
# Architecture Setup
# ============================================================================

hv_setup_arch() {
    case "$TARGET_ARCH" in
        aarch64)
            KERNEL_IMAGE="$BLOB_DIR/aarch64/Image"
            INITRAMFS="$BLOB_DIR/aarch64/initramfs.cpio.gz"
            ROOTFS_IMG="$BLOB_DIR/aarch64/rootfs.img"
            HV_CMD="xl"
            HV_CONSOLE="hvc0"
            ;;
        x86_64)
            KERNEL_IMAGE="$BLOB_DIR/x86_64/bzImage"
            INITRAMFS="$BLOB_DIR/x86_64/initramfs.cpio.gz"
            ROOTFS_IMG="$BLOB_DIR/x86_64/rootfs.img"
            HV_CMD="xl"
            HV_CONSOLE="hvc0"
            ;;
        *)
            log "ERROR" "Unsupported architecture: $TARGET_ARCH"
            exit 1
            ;;
    esac

    # Xen domain name: use container name if set, otherwise PID-based
    if [ -n "${CONTAINER_NAME:-}" ]; then
        HV_DOMNAME="vxn-${CONTAINER_NAME}"
    else
        HV_DOMNAME="vxn-$$"
    fi
    HV_VM_PID=""

    # Xen domain config path (generated at runtime)
    HV_XEN_CFG=""

    # Xen-specific: pass block device prefix via kernel cmdline
    # so preinit can find rootfs before /proc is mounted
    HV_BLK_PREFIX="xvd"
}

hv_check_accel() {
    # Xen IS the hypervisor - no KVM check needed
    USE_KVM="false"
    log "DEBUG" "Xen hypervisor (no KVM check needed)"
}

hv_skip_state_disk() {
    # Xen DomU Docker storage lives in the guest's overlay filesystem.
    # In daemon mode the domain stays running so storage persists naturally.
    # No need to create a 2GB disk image on Dom0.
    return 0
}

# ============================================================================
# Container Image Preparation (OCI pull via skopeo)
# ============================================================================

# Pull OCI image on the host so the input disk creation code can package it.
# Called from vrunner.sh before input disk creation. Modifies globals:
#   INPUT_PATH  - set to the OCI layout directory
#   INPUT_TYPE  - set to "oci"
#   DOCKER_CMD  - rewritten to the resolved entrypoint/command
#
# The host resolves the OCI entrypoint using jq (available on Dom0)
# so the guest doesn't need jq to determine what to execute.
# Stage per-run env (#20) onto the input disk as .vxn-env/env (0600). Mirrors the
# .vxn-ca staging; the guest sources it before exec. Never on any kernel cmdline.
_stage_vxn_env() {
    [ -n "$VXN_ENV_B64" ] || return 0
    mkdir -p "$1/.vxn-env" 2>/dev/null || return 0
    printf '%s' "$VXN_ENV_B64" | base64 -d > "$1/.vxn-env/env" 2>/dev/null
    chmod 600 "$1/.vxn-env/env" 2>/dev/null || true
    log "INFO" "Staged per-run env for the container ($(grep -c . "$1/.vxn-env/env" 2>/dev/null || echo 0) var(s))"
}

# Stage the per-run enforcement policy (#31) onto the input disk as
# .vxn-policy/policy (0600). Mirrors _stage_vxn_env; vxn-init reads it and
# applies the limits (Phase 1: cgroup v2 memory/pids/cpu) before exec. Off any
# kernel cmdline.
_stage_vxn_policy() {
    [ -n "$VXN_POLICY_B64" ] || return 0
    mkdir -p "$1/.vxn-policy" 2>/dev/null || return 0
    printf '%s' "$VXN_POLICY_B64" | base64 -d > "$1/.vxn-policy/policy" 2>/dev/null
    chmod 600 "$1/.vxn-policy/policy" 2>/dev/null || true
    log "INFO" "Staged per-run enforcement policy ($(grep -c . "$1/.vxn-policy/policy" 2>/dev/null || echo 0) directive(s))"
}

hv_prepare_container() {
    # Skip if user already provided --input
    [ -n "$INPUT_PATH" ] && return 0

    # Only act on "run" commands
    case "$DOCKER_CMD" in
        *" run "*)  ;;
        *)          return 0 ;;
    esac

    # Secret-safe per-run env (#20): AXIS passes container env as
    # --env-b64=<base64(KEY=VAL\n...)>. Pull it out of DOCKER_CMD HERE in dom0 so
    # the values are staged onto the per-run input disk (.vxn-env/env, like
    # .vxn-ca below) and STRIPPED from the command -- they never reach the
    # container DomU's kernel cmdline. The guest sources /mnt/input/.vxn-env/env
    # before exec. (The base64 value is transiently in dom0's argv here -- the
    # trusted control plane, like `docker run -e` on a host; a ssh/9p channel that
    # avoids dom0 argv entirely is a hardening follow-up.)
    VXN_ENV_B64=""
    case "$DOCKER_CMD" in
        *--env-b64=*)
            VXN_ENV_B64=$(printf '%s' "$DOCKER_CMD" | grep -oE '\-\-env-b64=[A-Za-z0-9+/=]+' | head -1)
            VXN_ENV_B64="${VXN_ENV_B64#--env-b64=}"
            DOCKER_CMD=$(printf '%s' "$DOCKER_CMD" | sed -E 's/ *--env-b64=[A-Za-z0-9+/=]+//')
            ;;
    esac

    # Nested enforcement (#31): AXIS passes the enforcement-relevant policy subset
    # as --policy-b64=<base64(KEY=VAL\n...)>. Same treatment as --env-b64 -- stage
    # it on the per-run input disk (.vxn-policy/policy) and STRIP it from the
    # command so it never reaches the DomU kernel cmdline. vxn-init applies it
    # (Phase 1: cgroup resource limits) before exec, inside the guest.
    VXN_POLICY_B64=""
    case "$DOCKER_CMD" in
        *--policy-b64=*)
            VXN_POLICY_B64=$(printf '%s' "$DOCKER_CMD" | grep -oE '\-\-policy-b64=[A-Za-z0-9+/=]+' | head -1)
            VXN_POLICY_B64="${VXN_POLICY_B64#--policy-b64=}"
            DOCKER_CMD=$(printf '%s' "$DOCKER_CMD" | sed -E 's/ *--policy-b64=[A-Za-z0-9+/=]+//')
            ;;
    esac

    # Check for skopeo
    if ! command -v skopeo >/dev/null 2>&1; then
        log "ERROR" "skopeo not found. Install skopeo for OCI image pulling."
        exit 1
    fi

    # Parse image name and any trailing command from "docker run [opts] <image> [cmd...]"
    # Uses word counting + cut to extract the user command portion from the
    # original string, preserving internal spaces (e.g., -c "echo hello && sleep 5").
    local args
    args=$(echo "$DOCKER_CMD" | sed 's/^[a-z]* run //')

    local image=""
    local user_cmd=""
    local skip_next=false
    local found_image=false
    local word_count=0
    for arg in $args; do
        if [ "$found_image" = "true" ]; then
            break
        fi
        word_count=$((word_count + 1))
        if [ "$skip_next" = "true" ]; then
            skip_next=false
            continue
        fi
        case "$arg" in
            --rm|--detach|-d|-i|--interactive|-t|--tty|--privileged|-it)
                ;;
            -p|--publish|-v|--volume|-e|--env|--name|--network|-w|--workdir|--entrypoint|-m|--memory|--cpus)
                skip_next=true
                ;;
            --publish=*|--volume=*|--env=*|--name=*|--network=*|--workdir=*|--entrypoint=*|--dns=*|--memory=*|--cpus=*)
                ;;
            -*)
                ;;
            *)
                image="$arg"
                found_image=true
                ;;
        esac
    done

    # Extract user command from original string using cut (preserves internal spaces)
    if [ "$found_image" = "true" ]; then
        user_cmd=$(echo "$args" | cut -d' ' -f$((word_count + 1))-)
        # If cut returns the whole string (no fields after image), clear it
        [ "$user_cmd" = "$args" ] && [ "$word_count" -ge "$(echo "$args" | wc -w)" ] && user_cmd=""
    fi

    # Strip /bin/sh -c wrapper from user command — the guest already wraps
    # with /bin/sh -c in exec_in_container_background(), so passing it through
    # would create nested shells with broken quoting.
    case "$user_cmd" in
        "/bin/sh -c "*)  user_cmd="${user_cmd#/bin/sh -c }" ;;
        "sh -c "*)       user_cmd="${user_cmd#sh -c }" ;;
    esac

    if [ -z "$image" ]; then
        log "DEBUG" "hv_prepare_container: no image found in DOCKER_CMD"
        return 0
    fi

    # Local rootfs directory: when the "image" is an absolute path to a
    # directory that looks like a root filesystem (has bin/ or usr/), use it
    # directly as the container rootfs instead of pulling from a registry. Lets
    # `vxn run <dir>` run any local rootfs/bundle (e.g. a `vxn bundle` output).
    # The input disk builder (vrunner.sh) turns a dir into an ext4 image via
    # `mke2fs -d`, and the guest direct-mounts it.
    case "$image" in
        /*)
            if [ -d "$image" ] && { [ -d "$image/bin" ] || [ -d "$image/usr" ]; }; then
                INPUT_PATH="$image"
                INPUT_TYPE="dir"
                log "INFO" "Using local rootfs directly: $image"
                # DomU still inherits dom0's corporate CA(s) (same as the pull
                # path) so the container trusts a TLS-intercepting proxy.
                if ls /usr/local/share/ca-certificates/*.crt >/dev/null 2>&1; then
                    mkdir -p "$image/.vxn-ca"
                    cp /usr/local/share/ca-certificates/*.crt "$image/.vxn-ca/" 2>/dev/null || true
                    log "INFO" "Staged dom0 CA cert(s) for the container trust store"
                fi
                _stage_vxn_env "$image"
                _stage_vxn_policy "$image"
                return 0
            fi
            ;;
    esac

    # Provisioned rootfs (vxn provision <name>): a bare image name resolving to a
    # cached rootfs at ~/.vxn/rootfs/<name>. Direct-mount it (no OCI, no
    # registry) and apply the recorded ENTRYPOINT/CMD so `vxn run <name>` runs the
    # tool. Checked BEFORE the OCI cache/registry path so a provisioned name wins;
    # names that were never provisioned fall through to the OCI path unchanged.
    local prov_cache="${VXN_ROOTFS_CACHE:-$HOME/.vxn/rootfs}"
    if [ -d "$prov_cache/$image" ] && { [ -d "$prov_cache/$image/bin" ] || [ -d "$prov_cache/$image/usr" ]; }; then
        INPUT_PATH="$prov_cache/$image"
        INPUT_TYPE="dir"
        log "INFO" "Using provisioned rootfs: $image"
        local P_ENTRYPOINT="" P_CMD="" P_WORKDIR="" P_ENV="" _rc=""
        [ -f "$prov_cache/$image.conf" ] && . "$prov_cache/$image.conf"
        # entrypoint + (user command if given, else the recorded CMD)
        _rc="$P_ENTRYPOINT"
        if [ -n "$user_cmd" ]; then _rc="$_rc${_rc:+ }$user_cmd"
        elif [ -n "$P_CMD" ]; then _rc="$_rc${_rc:+ }$P_CMD"; fi
        [ -n "$_rc" ] && { DOCKER_CMD="$_rc"; log "INFO" "Provisioned command: $_rc"; }
        if ls /usr/local/share/ca-certificates/*.crt >/dev/null 2>&1; then
            mkdir -p "$INPUT_PATH/.vxn-ca"
            cp /usr/local/share/ca-certificates/*.crt "$INPUT_PATH/.vxn-ca/" 2>/dev/null || true
        fi
        _stage_vxn_env "$INPUT_PATH"
        _stage_vxn_policy "$INPUT_PATH"
        return 0
    fi

    local oci_dir="$TEMP_DIR/oci-image"
    local skopeo_log="$TEMP_DIR/skopeo.log"

    # Local image cache (#28): if this image was previously `vxn pull`ed or
    # `vxn load`ed, reuse it instead of hitting the registry every run. The cache
    # (~/.vxn/images) is the same store the frontend's pull/load/ls/rm/tag ops
    # populate -- refs/<normalized-name, / -> _> symlinks a content-addressed
    # store/sha256/<digest> OCI dir. hv_prepare_container runs in the same dom0
    # as those ops, so it sees the same cache. On a hit we copy the cached OCI
    # into oci_dir and skip the network pull; the CA + per-run env (#20) +
    # entrypoint resolution below run unchanged either way. The runner doesn't
    # source the frontend, so name normalization is inlined here to match
    # vcontainer-common.sh's vxn_normalize_image_name.
    local vxn_cache="${VXN_IMAGE_CACHE:-$HOME/.vxn/images}"
    local cache_name="$image"
    case "$cache_name" in
        *.*/*) ;;                                    # has registry (dot before /)
        */*)   cache_name="docker.io/$cache_name" ;; # namespace, no registry
        *)     cache_name="docker.io/library/$cache_name" ;;
    esac
    case "$cache_name" in *:*) ;; *) cache_name="$cache_name:latest" ;; esac
    local cache_ref="$vxn_cache/refs/$(printf '%s' "$cache_name" | tr '/' '_')"

    if [ -L "$cache_ref" ] && [ -d "$cache_ref" ]; then
        log "INFO" "Using cached image: $cache_name (no registry pull)"
        cp -a "$(readlink -f "$cache_ref")" "$oci_dir"
        INPUT_PATH="$oci_dir"
        INPUT_TYPE="oci"
    elif skopeo copy "docker://$image" "oci:$oci_dir:latest" > "$skopeo_log" 2>&1; then
        INPUT_PATH="$oci_dir"
        INPUT_TYPE="oci"
        log "INFO" "OCI image pulled to $oci_dir"
    else
        log "ERROR" "Failed to pull image: $image"
        [ -f "$skopeo_log" ] && while IFS= read -r line; do
            log "ERROR" "skopeo: $line"
        done < "$skopeo_log"
        exit 1
    fi

    # Extract the OCI layers into a flat rootfs HERE (dom0 side, ample disk) so
    # the input disk carries the READY rootfs and the guest DIRECT-MOUNTS it rw
    # (vxn-init find_container_rootfs bin/usr path -- the same path `vxn run
    # <dir>` uses). Shipping the OCI blobs and unpacking in the guest instead
    # overflows the DomU's RAM tmpfs: the DomU root is read-only, so extraction
    # lands in RAM, and a 512MB DomU truncated a ~300MB binary, which then
    # SIGBUSed when mmap'd. Extracting on dom0 also skips a slow guest-boot
    # unpack. (Layers apply in order; OCI whiteouts are not processed -- same
    # basic behavior the guest extractor had, fine for additive images.)
    local rootfs_dir="$TEMP_DIR/rootfs"
    mkdir -p "$rootfs_dir"
    local _mdigest _mfile _ldigest _lfile
    _mdigest=$(jq -r '.manifests[0].digest' "$oci_dir/index.json" 2>/dev/null)
    _mfile="$oci_dir/blobs/${_mdigest/://}"
    if ! command -v jq >/dev/null 2>&1 || [ ! -f "$_mfile" ]; then
        log "ERROR" "cannot read OCI manifest to extract layers for $image"
        exit 1
    fi
    for _ldigest in $(jq -r '.layers[].digest' "$_mfile" 2>/dev/null); do
        _lfile="$oci_dir/blobs/${_ldigest/://}"
        [ -f "$_lfile" ] || { log "ERROR" "layer blob missing: $_ldigest"; exit 1; }
        # Do NOT silence tar: an out-of-space extract is exactly what truncated
        # the binary in the guest; fail loudly instead.
        if ! tar -xf "$_lfile" -C "$rootfs_dir" 2>"$TEMP_DIR/tar.log"; then
            log "ERROR" "layer extract failed ($_ldigest):"
            while IFS= read -r _tl; do log "ERROR" "  tar: $_tl"; done < "$TEMP_DIR/tar.log"
            exit 1
        fi
    done
    # The ready rootfs is now the input; the guest direct-mounts it (no RAM
    # unpack). Overrides the INPUT_PATH=oci_dir set in the pull/cache-hit block.
    INPUT_PATH="$rootfs_dir"
    INPUT_TYPE="dir"

    # DomU inherits dom0's corporate CA(s): stage them INTO the rootfs so the
    # guest init installs them into the container trust store (containers doing
    # their own TLS/network ops then trust a proxy CA too). With the rootfs as
    # the input disk, .vxn-ca / .vxn-env sit at its root, where the guest already
    # looks (/mnt/input/.vxn-ca, /mnt/input/.vxn-env).
    if ls /usr/local/share/ca-certificates/*.crt >/dev/null 2>&1; then
        mkdir -p "$rootfs_dir/.vxn-ca"
        cp /usr/local/share/ca-certificates/*.crt "$rootfs_dir/.vxn-ca/" 2>/dev/null || true
        log "INFO" "Staged dom0 CA cert(s) for the container trust store"
    fi
    _stage_vxn_env "$rootfs_dir"
    _stage_vxn_policy "$rootfs_dir"

    # Resolve entrypoint from OCI config on the host (jq available here).
    # Rewrite DOCKER_CMD so the guest receives the actual command to exec,
    # avoiding any dependency on jq inside the minimal guest rootfs.
    local resolved_cmd="$user_cmd"
    if [ -z "$resolved_cmd" ] && command -v jq >/dev/null 2>&1; then
        local entrypoint="" oci_cmd=""
        local manifest_digest config_digest manifest_file config_file
        manifest_digest=$(jq -r '.manifests[0].digest' "$oci_dir/index.json" 2>/dev/null)
        manifest_file="$oci_dir/blobs/${manifest_digest/://}"
        if [ -f "$manifest_file" ]; then
            config_digest=$(jq -r '.config.digest' "$manifest_file" 2>/dev/null)
            config_file="$oci_dir/blobs/${config_digest/://}"
            if [ -f "$config_file" ]; then
                entrypoint=$(jq -r '(.config.Entrypoint // []) | join(" ")' "$config_file" 2>/dev/null)
                oci_cmd=$(jq -r '(.config.Cmd // []) | join(" ")' "$config_file" 2>/dev/null)
            fi
        fi
        if [ -n "$entrypoint" ]; then
            resolved_cmd="$entrypoint"
            [ -n "$oci_cmd" ] && resolved_cmd="$resolved_cmd $oci_cmd"
        elif [ -n "$oci_cmd" ]; then
            resolved_cmd="$oci_cmd"
        fi
        log "INFO" "Resolved OCI entrypoint: $resolved_cmd"
    fi

    if [ -n "$resolved_cmd" ]; then
        DOCKER_CMD="$resolved_cmd"
        log "INFO" "DOCKER_CMD rewritten to: $DOCKER_CMD"
    fi
}

hv_find_command() {
    if ! command -v xl >/dev/null 2>&1; then
        log "ERROR" "xl (Xen toolstack) not found. Install xen-tools-xl."
        exit 1
    fi
    log "DEBUG" "Using Xen xl toolstack"
}

hv_get_console_device() {
    echo "$HV_CONSOLE"
}

# ============================================================================
# VM Configuration Building
# ============================================================================

# Internal: accumulate disk config entries
_XEN_DISKS=()
_XEN_VIF=""
_XEN_9P=()

hv_build_disk_opts() {
    _XEN_DISKS=()

    # Rootfs (read-only)
    _XEN_DISKS+=("'format=raw,vdev=xvda,access=ro,target=$ROOTFS_IMG'")

    # Input disk (if any) - check if DISK_OPTS is set (means input disk was created)
    if [ -n "$DISK_OPTS" ]; then
        # Extract the file path from QEMU-style DISK_OPTS
        local input_file
        input_file=$(echo "$DISK_OPTS" | sed -n 's/.*file=\([^,]*\).*/\1/p')
        if [ -n "$input_file" ]; then
            _XEN_DISKS+=("'format=raw,vdev=xvdb,access=rw,target=$input_file'")
        fi
    fi

    # State disk (if any)
    if [ -n "$STATE_DISK_OPTS" ]; then
        local state_file
        state_file=$(echo "$STATE_DISK_OPTS" | sed -n 's/.*file=\([^,]*\).*/\1/p')
        if [ -n "$state_file" ]; then
            _XEN_DISKS+=("'format=raw,vdev=xvdc,access=rw,target=$state_file'")
        fi
    fi
}

hv_build_network_opts() {
    _XEN_VIF=""
    if [ "$NETWORK" = "true" ]; then
        # Use default bridge networking
        # Xen will attach the vif to xenbr0 or the default bridge
        _XEN_VIF="'bridge=xenbr0'"
    fi
    # If no network, _XEN_VIF stays empty → vif = [] in config
}

hv_build_9p_opts() {
    local share_dir="$1"
    local share_tag="$2"
    # Xen 9p (xen_9pfsd) is not reliable in all environments (e.g. nested
    # QEMU→Xen). Keep the interface for future use but don't depend on it
    # for daemon IPC — we use serial/PTY + socat instead.
    _XEN_9P+=("'tag=$share_tag,path=$share_dir,security_model=none,type=xen_9pfsd'")
}

hv_build_daemon_opts() {
    HV_DAEMON_OPTS=""
    # Xen daemon mode uses hvc0 with serial='pty' for bidirectional IPC.
    # The PTY is created on Dom0 and bridged to a Unix socket via socat.
    # This is the same approach runx used (serial_start).
}

hv_build_vm_cmd() {
    # For Xen, we generate a domain config file instead of a command line
    # HV_OPTS is not used directly; the config file is written by _write_xen_config
    HV_OPTS=""
}

# ============================================================================
# Static IP allocation (VXN_NET_MODE=static, the default)
# ============================================================================
# Pick a unique address on the DomU bridge subnet and hand it to the guest on
# the kernel cmdline, so the guest configures statically and skips the ~3s
# udhcpc round-trip. Range is OUTSIDE dnsmasq's DHCP pool (10.0.100.50-200) so
# static leases never collide with DHCP leases. Leases are atomic (mkdir) and
# self-cleaning: a lease whose owning domain is no longer running is reaped and
# reused, so a crashed/killed container never permanently leaks its address --
# and the single hardcoded DHCP fallback in the guest (which every DomU shares,
# hence collides) is avoided entirely. If the pool is exhausted or mode!=static,
# emit nothing and the guest falls back to DHCP.
#
# NOTE: currently inlined here; the same logic is added to vxn-oci-runtime for
# the docker/podman/ctr path. Extract to a shared vxn-ipam helper if it grows.
VXN_IPAM_DIR="${VXN_IPAM_DIR:-/var/lib/vxn-ipam}"
VXN_NET_BASE="${VXN_NET_BASE:-10.0.100}"          # /24 base (hosts .START-.END)
VXN_NET_RANGE_START="${VXN_NET_RANGE_START:-201}" # outside dnsmasq pool .50-.200
VXN_NET_RANGE_END="${VXN_NET_RANGE_END:-254}"
VXN_NET_GW="${VXN_NET_GW:-10.0.100.1}"
VXN_NET_DNS="${VXN_NET_DNS:-10.0.100.1}"
VXN_NET_PREFIXLEN="${VXN_NET_PREFIXLEN:-24}"

# vxn_ipam_alloc <owner-domain-name> -> echoes an IP, or nothing if exhausted.
vxn_ipam_alloc() {
    local id="$1" ip lease owner n
    # Explicit pin wins (VXN_NET_IP=10.0.100.210 for a deterministic address).
    [ -n "${VXN_NET_IP:-}" ] && { echo "$VXN_NET_IP"; return 0; }
    mkdir -p "$VXN_IPAM_DIR" 2>/dev/null || return 0
    # Reap stale leases: owner domain no longer known to xl.
    for lease in "$VXN_IPAM_DIR/$VXN_NET_BASE".*; do
        [ -d "$lease" ] || continue
        owner=$(cat "$lease/owner" 2>/dev/null)
        [ -n "$owner" ] && ! xl domid "$owner" >/dev/null 2>&1 && rm -rf "$lease"
    done
    # Claim the first free slot -- mkdir is atomic, so concurrent allocs can't
    # both win the same address.
    n="$VXN_NET_RANGE_START"
    while [ "$n" -le "$VXN_NET_RANGE_END" ]; do
        ip="$VXN_NET_BASE.$n"
        if mkdir "$VXN_IPAM_DIR/$ip" 2>/dev/null; then
            echo "$id" > "$VXN_IPAM_DIR/$ip/owner" 2>/dev/null
            echo "$ip"
            return 0
        fi
        n=$((n + 1))
    done
    return 0   # pool exhausted -> caller emits nothing -> guest DHCPs
}

# Internal: write Xen domain config file
_write_xen_config() {
    local kernel_append="$1"
    local config_path="$2"

    # Build disk array
    local disk_array=""
    for d in "${_XEN_DISKS[@]}"; do
        if [ -n "$disk_array" ]; then
            disk_array="$disk_array, $d"
        else
            disk_array="$d"
        fi
    done

    # Build vif array
    local vif_array=""
    if [ -n "$_XEN_VIF" ]; then
        vif_array="$_XEN_VIF"
    fi

    # Determine guest type per architecture:
    #   x86_64: PV guests work (paravirtualized, no HVM needed)
    #   aarch64: ARM Xen only supports PVH-style guests (no PV)
    local xen_type="pv"
    case "$TARGET_ARCH" in
        aarch64) xen_type="pvh" ;;
    esac

    # Memory and vCPUs - configurable via environment
    local xen_memory="${VXN_MEMORY:-512}"
    local xen_vcpus="${VXN_VCPUS:-2}"

    # DomU kernel cmdline additions, based on where the SDK is running:
    #   * AMD auto-detect: the guest kernel's print_s5_reset_status_mmio initcall
    #     does a raw ioread32 on AMD FCH MMIO (0xFED803C0) -- valid on AMD bare
    #     metal, but unmapped in a Xen PV DomU -> page fault in PID 1 ->
    #     "Attempted to kill init" panic. Blacklisting it is a no-op on Intel
    #     (never called there). Key off dom0's CPU vendor: dom0 runs -cpu host,
    #     so it sees the real host -- AMD on an AMD laptop, Intel on the build
    #     box. The proper fix is guarding that initcall in the DomU kernel (TODO);
    #     this is the no-kernel-rebuild workaround.
    #   * VXN_DOMU_CMDLINE_EXTRA: arbitrary extra DomU cmdline (dom0 env / config).
    local domu_extra=""
    if grep -qi "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
        domu_extra="$domu_extra initcall_blacklist=print_s5_reset_status_mmio"
    fi

    # Static IP (VXN_NET_MODE=static, default): allocate an address and emit it
    # on the guest cmdline so the guest skips udhcpc. Only when networking is on;
    # empty allocation (pool exhausted) or VXN_NET_MODE=dhcp -> guest DHCPs.
    if [ "$NETWORK" = "true" ] && [ "${VXN_NET_MODE:-static}" = "static" ]; then
        local _vxn_ip
        _vxn_ip=$(vxn_ipam_alloc "$HV_DOMNAME")
        if [ -n "$_vxn_ip" ]; then
            domu_extra="$domu_extra ${CMDLINE_PREFIX}_ip=$_vxn_ip ${CMDLINE_PREFIX}_gw=$VXN_NET_GW ${CMDLINE_PREFIX}_prefixlen=$VXN_NET_PREFIXLEN ${CMDLINE_PREFIX}_dns=$VXN_NET_DNS"
            log "INFO" "Static IP allocated: $_vxn_ip (gw $VXN_NET_GW)"
        fi
    fi

    [ -n "${VXN_DOMU_CMDLINE_EXTRA:-}" ] && domu_extra="$domu_extra $VXN_DOMU_CMDLINE_EXTRA"

    # Initial terminal geometry for interactive runs (captured in
    # hv_start_vm_foreground). The guest's vxn-init.sh applies it to hvc0 via
    # stty before exec so full-screen TUIs aren't clipped to 80x25.
    if [ -n "${_VXN_WIN_ROWS:-}" ] && [ -n "${_VXN_WIN_COLS:-}" ]; then
        domu_extra="$domu_extra vcontainer.rows=$_VXN_WIN_ROWS vcontainer.cols=$_VXN_WIN_COLS"
    fi

    cat > "$config_path" <<XENEOF
# Auto-generated Xen domain config for vxn
name = "$HV_DOMNAME"
type = "$xen_type"
memory = $xen_memory
vcpus = $xen_vcpus

kernel = "$KERNEL_IMAGE"
ramdisk = "$INITRAMFS"
extra = "console=hvc0 quiet loglevel=0 init=/init vcontainer.blk=xvd vcontainer.init=/vxn-init.sh$domu_extra $kernel_append"

disk = [ $disk_array ]
vif = [ $vif_array ]

serial = 'pty'

on_poweroff = "destroy"
on_reboot = "destroy"
on_crash = "destroy"
XENEOF

    # Add 9p config if any shares were requested
    if [ ${#_XEN_9P[@]} -gt 0 ]; then
        local p9_array=""
        for p in "${_XEN_9P[@]}"; do
            if [ -n "$p9_array" ]; then
                p9_array="$p9_array, $p"
            else
                p9_array="$p"
            fi
        done
        echo "p9 = [ $p9_array ]" >> "$config_path"
    fi

    log "DEBUG" "Xen config written to $config_path"
}

# ============================================================================
# VM Lifecycle
# ============================================================================

hv_start_vm_background() {
    local kernel_append="$1"
    local log_file="$2"
    local timeout_val="$3"

    # Write domain config
    HV_XEN_CFG="${TEMP_DIR:-/tmp}/vxn-$$.cfg"
    _write_xen_config "$kernel_append" "$HV_XEN_CFG"

    # Create the domain
    [ "${VXN_TIMING:-0}" = "1" ] && echo "DTIME xlcreate_start $(date +%s.%N)" >&2
    xl create "$HV_XEN_CFG" >> "$log_file" 2>&1
    [ "${VXN_TIMING:-0}" = "1" ] && echo "DTIME xlcreate_done $(date +%s.%N)" >&2

    # Xen domains don't have a PID on Dom0 — xl manages them by name.
    # For daemon mode, start a lightweight monitor process that stays alive
    # while the domain exists. This gives vcontainer-common.sh a real PID
    # to check in /proc/$pid for daemon_is_running().
    HV_VM_PID="$$"

    if [ "$DAEMON_MODE" = "start" ]; then
        # Daemon mode: get the domain's hvc0 PTY for direct I/O.
        # serial='pty' in the xl config creates a PTY on Dom0.
        # We read/write this PTY directly — no socat bridge needed.
        local domid
        domid=$(xl domid "$HV_DOMNAME" 2>/dev/null)
        if [ -n "$domid" ]; then
            _XEN_PTY=$(xenstore-read "/local/domain/$domid/console/tty" 2>/dev/null)
            if [ -n "$_XEN_PTY" ]; then
                log "DEBUG" "Domain $HV_DOMNAME (domid $domid) console PTY: $_XEN_PTY"
                echo "$_XEN_PTY" > "$DAEMON_SOCKET_DIR/daemon.pty"
            else
                log "ERROR" "Could not read console PTY from xenstore for domid $domid"
            fi
        else
            log "ERROR" "Could not get domid for $HV_DOMNAME"
        fi

        # Monitor process: stays alive while domain exists.
        # vcontainer-common.sh checks /proc/$pid → alive means daemon running.
        # When domain dies (xl destroy, guest reboot), monitor exits.
        #
        # Detach the monitor's stdio from the invoking shell: in daemon
        # mode this process outlives vrunner.sh, and any inherited fd
        # would keep a pipe-wrapped caller (e.g. subprocess.run with
        # capture_output=True) blocked in communicate() until the domain
        # exits. Redirect fd 0/1/2 and disown.
        local _domname="$HV_DOMNAME"
        (while xl list "$_domname" >/dev/null 2>&1; do sleep 10; done) \
            </dev/null >/dev/null 2>&1 &
        HV_VM_PID=$!
        disown $! 2>/dev/null || true
    else
        # Ephemeral mode: capture guest console (hvc0) to log file
        # so the monitoring loop in vrunner.sh can see output markers.
        # Detach stdin so the background reader doesn't hold the caller's
        # fd 0 open.
        stdbuf -oL xl console "$HV_DOMNAME" </dev/null >> "$log_file" 2>&1 &
        _XEN_CONSOLE_PID=$!
        log "DEBUG" "Console capture started (PID: $_XEN_CONSOLE_PID)"
    fi
}

hv_start_vm_foreground() {
    local kernel_append="$1"

    # Capture the controlling terminal's window size so the guest can set its
    # hvc0 geometry before exec. xl console shuttles raw bytes but never relays
    # winsize into the guest, so the guest tty otherwise defaults to 80x25 and
    # full-screen TUIs (claude's Ink UI) render clipped. ssh -tt already sized
    # this pty (config-a) / it's the real terminal (config-b), so `stty size`
    # here reads the correct dimensions. Best-effort, integers only (the values
    # ride the kernel cmdline -- reject anything non-numeric). _VXN_WIN_* are
    # read by _write_xen_config below (same shell).
    _VXN_WIN_ROWS=""; _VXN_WIN_COLS=""
    if [ -t 0 ]; then
        _vxn_sz=$(stty size 2>/dev/null)   # "rows cols"
        _vxn_r=${_vxn_sz%% *}; _vxn_c=${_vxn_sz##* }
        case "$_vxn_r$_vxn_c" in
            ''|*[!0-9]*) ;;                 # non-numeric -> leave unset
            *) [ "$_vxn_r" -gt 0 ] && [ "$_vxn_c" -gt 0 ] && { _VXN_WIN_ROWS=$_vxn_r; _VXN_WIN_COLS=$_vxn_c; } ;;
        esac
    fi

    HV_XEN_CFG="${TEMP_DIR:-/tmp}/vxn-$$.cfg"
    _write_xen_config "$kernel_append" "$HV_XEN_CFG"

    # Create domain and attach console. Filter xl's cosmetic "Parsing config
    # from <file>" banner off stderr while leaving genuine create errors (also
    # on stderr) visible on the interactive console; stdin/stdout stay wired to
    # the terminal for the guest console. This is the -it path -- the background
    # path (hv_start_vm) already redirects to a log file, so only this one leaked
    # the banner to the user. bash process substitution keeps the filter to the
    # single stream without disturbing the tty.
    xl create -c "$HV_XEN_CFG" 2> >(grep -v '^Parsing config from ' >&2)
}

hv_is_vm_running() {
    xl list "$HV_DOMNAME" >/dev/null 2>&1
}

hv_wait_vm_exit() {
    local timeout="${1:-30}"
    for i in $(seq 1 "$timeout"); do
        hv_is_vm_running || return 0
        sleep 1
    done
    return 1
}

hv_stop_vm() {
    log "INFO" "Shutting down Xen domain $HV_DOMNAME..."
    xl shutdown "$HV_DOMNAME" 2>/dev/null || true

    # Wait for graceful shutdown
    hv_wait_vm_exit 15 || {
        log "WARN" "Domain didn't shut down gracefully, destroying..."
        hv_destroy_vm
    }
}

hv_destroy_vm() {
    xl destroy "$HV_DOMNAME" 2>/dev/null || true

    # Clean up console capture (ephemeral mode)
    if [ -n "${_XEN_CONSOLE_PID:-}" ]; then
        kill $_XEN_CONSOLE_PID 2>/dev/null || true
    fi
}

hv_get_vm_id() {
    echo "$HV_DOMNAME"
}

# ============================================================================
# Port Forwarding (iptables NAT for Xen bridge networking)
# ============================================================================

# Track iptables rules for cleanup
_XEN_IPTABLES_RULES=()

hv_setup_port_forwards() {
    if [ ${#PORT_FORWARDS[@]} -eq 0 ]; then
        return
    fi

    # Get guest IP from Xen network config
    # Wait briefly for the guest to get an IP
    local guest_ip=""
    for attempt in $(seq 1 30); do
        guest_ip=$(xl network-list "$HV_DOMNAME" 2>/dev/null | awk 'NR>1{print $4}' | head -1)
        if [ -n "$guest_ip" ] && [ "$guest_ip" != "-" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "$guest_ip" ] || [ "$guest_ip" = "-" ]; then
        log "WARN" "Could not determine guest IP for port forwarding"
        return
    fi

    log "INFO" "Guest IP: $guest_ip"

    for pf in "${PORT_FORWARDS[@]}"; do
        local host_port="${pf%%:*}"
        local rest="${pf#*:}"
        local container_port="${rest%%/*}"
        local proto="tcp"
        if [[ "$rest" == */* ]]; then
            proto="${rest##*/}"
        fi

        iptables -t nat -A PREROUTING -p "$proto" --dport "$host_port" \
            -j DNAT --to-destination "$guest_ip:$host_port" 2>/dev/null || true
        iptables -A FORWARD -p "$proto" -d "$guest_ip" --dport "$host_port" \
            -j ACCEPT 2>/dev/null || true
        _XEN_IPTABLES_RULES+=("$proto:$host_port:$guest_ip")
        log "INFO" "Port forward: host:$host_port -> $guest_ip:$host_port ($proto)"
    done
}

hv_cleanup_port_forwards() {
    for rule in "${_XEN_IPTABLES_RULES[@]}"; do
        local proto="${rule%%:*}"
        local rest="${rule#*:}"
        local host_port="${rest%%:*}"
        local guest_ip="${rest#*:}"

        iptables -t nat -D PREROUTING -p "$proto" --dport "$host_port" \
            -j DNAT --to-destination "$guest_ip:$host_port" 2>/dev/null || true
        iptables -D FORWARD -p "$proto" -d "$guest_ip" --dport "$host_port" \
            -j ACCEPT 2>/dev/null || true
    done
    _XEN_IPTABLES_RULES=()
}

# ============================================================================
# Idle Timeout
# ============================================================================

hv_idle_shutdown() {
    # For Xen, use xl shutdown for graceful stop
    xl shutdown "$HV_DOMNAME" 2>/dev/null || true
}

# ============================================================================
# Daemon Lifecycle (Xen-specific overrides)
# ============================================================================
# Xen domains persist via xl, not as child processes. The PID saved by
# vrunner.sh is just a placeholder. These hooks let daemon_is_running()
# and daemon_stop() work correctly for Xen.

# Persist domain name alongside PID file so we can recover it on reconnect
_xen_domname_file() {
    echo "${DAEMON_SOCKET_DIR:-/tmp}/daemon.domname"
}

hv_daemon_save_state() {
    echo "$HV_DOMNAME" > "$(_xen_domname_file)"
}

hv_daemon_load_state() {
    local f="$(_xen_domname_file)"
    if [ -f "$f" ]; then
        HV_DOMNAME=$(cat "$f" 2>/dev/null)
    fi
}

hv_daemon_is_running() {
    hv_daemon_load_state
    [ -n "$HV_DOMNAME" ] && xl list "$HV_DOMNAME" >/dev/null 2>&1
}

# PTY-based daemon readiness check.
# The guest emits ===PONG=== on hvc0 at daemon startup and in response to PING.
# We read the PTY (saved by hv_start_vm_background) looking for this marker.
hv_daemon_ping() {
    local pty_file="$DAEMON_SOCKET_DIR/daemon.pty"
    [ -f "$pty_file" ] || return 1
    local pty
    pty=$(cat "$pty_file")
    [ -c "$pty" ] || return 1

    # Open PTY for read/write on fd 3
    exec 3<>"$pty"

    # Send PING (guest also emits PONG at startup)
    echo "===PING===" >&3

    # Read lines looking for PONG (skip boot messages, log lines)
    local line
    while IFS= read -t 5 -r line <&3; do
        line=$(echo "$line" | tr -d '\r')
        case "$line" in
            *"===PONG==="*) exec 3<&- 3>&-; return 0 ;;
        esac
    done

    exec 3<&- 3>&- 2>/dev/null
    return 1
}

# PTY-based daemon command send.
# Writes base64-encoded command to PTY, reads response with markers.
# Same protocol as socat-based daemon_send in vrunner.sh.
hv_daemon_send() {
    local cmd="$1"
    local pty_file="$DAEMON_SOCKET_DIR/daemon.pty"
    [ -f "$pty_file" ] || { log "ERROR" "No daemon PTY file"; return 1; }
    local pty
    pty=$(cat "$pty_file")
    [ -c "$pty" ] || { log "ERROR" "PTY $pty not a character device"; return 1; }

    # Update activity timestamp
    touch "$DAEMON_SOCKET_DIR/activity" 2>/dev/null || true

    # Encode command
    local cmd_b64
    cmd_b64=$(echo -n "$cmd" | base64 -w0)

    # Open PTY for read/write on fd 3
    exec 3<>"$pty"

    # Drain any pending output (boot messages, prior log lines)
    while IFS= read -t 0.5 -r _discard <&3; do :; done

    # Send command
    echo "$cmd_b64" >&3

    # Read response with markers
    local EXIT_CODE=0
    local in_output=false
    local line
    while IFS= read -t 60 -r line <&3; do
        line=$(echo "$line" | tr -d '\r')
        case "$line" in
            *"===OUTPUT_START==="*)
                in_output=true
                ;;
            *"===OUTPUT_END==="*)
                in_output=false
                ;;
            *"===EXIT_CODE="*"==="*)
                EXIT_CODE=$(echo "$line" | sed 's/.*===EXIT_CODE=\([0-9]*\)===/\1/')
                ;;
            *"===END==="*)
                break
                ;;
            *)
                if [ "$in_output" = "true" ]; then
                    echo "$line"
                fi
                ;;
        esac
    done

    exec 3<&- 3>&- 2>/dev/null
    return ${EXIT_CODE:-0}
}

# Run a container in a memres (persistent) DomU.
# Hot-plugs an input disk, sends ===RUN_CONTAINER=== command via PTY,
# reads output, detaches disk.
# Usage: hv_daemon_run_container <resolved_cmd> <input_disk_path>
hv_daemon_run_container() {
    local cmd="$1"
    local input_disk="$2"

    hv_daemon_load_state
    if [ -z "$HV_DOMNAME" ]; then
        log "ERROR" "No memres domain name"
        return 1
    fi

    # Hot-plug the input disk as xvdb (read-only)
    if [ -n "$input_disk" ] && [ -f "$input_disk" ]; then
        log "INFO" "Hot-plugging container disk to $HV_DOMNAME..."
        xl block-attach "$HV_DOMNAME" "format=raw,vdev=xvdb,access=ro,target=$input_disk" 2>/dev/null || {
            log "ERROR" "Failed to attach block device"
            return 1
        }
        sleep 1  # Let the kernel register the device
    fi

    # Build the command line: ===RUN_CONTAINER===<cmd_b64>
    local raw_line="===RUN_CONTAINER==="
    if [ -n "$cmd" ]; then
        raw_line="${raw_line}$(echo -n "$cmd" | base64 -w0)"
    fi

    # Send via PTY and read response (same protocol as hv_daemon_send)
    local pty_file="$DAEMON_SOCKET_DIR/daemon.pty"
    [ -f "$pty_file" ] || { log "ERROR" "No daemon PTY file"; return 1; }
    local pty
    pty=$(cat "$pty_file")
    [ -c "$pty" ] || { log "ERROR" "PTY $pty not a character device"; return 1; }

    touch "$DAEMON_SOCKET_DIR/activity" 2>/dev/null || true

    exec 3<>"$pty"

    # Drain pending output
    while IFS= read -t 0.5 -r _discard <&3; do :; done

    # Send command
    echo "$raw_line" >&3

    # Read response with markers
    local EXIT_CODE=0
    local in_output=false
    local line
    while IFS= read -t 120 -r line <&3; do
        line=$(echo "$line" | tr -d '\r')
        case "$line" in
            *"===OUTPUT_START==="*)
                in_output=true
                ;;
            *"===OUTPUT_END==="*)
                in_output=false
                ;;
            *"===EXIT_CODE="*"==="*)
                EXIT_CODE=$(echo "$line" | sed 's/.*===EXIT_CODE=\([0-9]*\)===/\1/')
                ;;
            *"===ERROR==="*)
                in_output=true
                ;;
            *"===END==="*)
                break
                ;;
            *)
                if [ "$in_output" = "true" ]; then
                    echo "$line"
                fi
                ;;
        esac
    done

    exec 3<&- 3>&- 2>/dev/null

    # Detach the input disk
    if [ -n "$input_disk" ] && [ -f "$input_disk" ]; then
        log "DEBUG" "Detaching container disk from $HV_DOMNAME..."
        xl block-detach "$HV_DOMNAME" xvdb 2>/dev/null || true
    fi

    return ${EXIT_CODE:-0}
}

hv_daemon_stop() {
    hv_daemon_load_state
    if [ -z "$HV_DOMNAME" ]; then
        return 0
    fi

    log "INFO" "Shutting down Xen domain $HV_DOMNAME..."

    # Send shutdown command via PTY (graceful guest shutdown)
    local pty_file="$DAEMON_SOCKET_DIR/daemon.pty"
    if [ -f "$pty_file" ]; then
        local pty
        pty=$(cat "$pty_file")
        if [ -c "$pty" ]; then
            echo "===SHUTDOWN===" > "$pty" 2>/dev/null || true
            sleep 2
        fi
    fi

    # Try graceful xl shutdown
    if xl list "$HV_DOMNAME" >/dev/null 2>&1; then
        xl shutdown "$HV_DOMNAME" 2>/dev/null || true
        # Wait for domain to disappear
        for i in $(seq 1 15); do
            xl list "$HV_DOMNAME" >/dev/null 2>&1 || break
            sleep 1
        done
    fi

    # Force destroy if still running
    if xl list "$HV_DOMNAME" >/dev/null 2>&1; then
        log "WARN" "Domain didn't shut down gracefully, destroying..."
        xl destroy "$HV_DOMNAME" 2>/dev/null || true
    fi

    # Kill monitor process (PID stored in daemon.pid)
    local pid_file="$DAEMON_SOCKET_DIR/daemon.pid"
    if [ -f "$pid_file" ]; then
        local mpid
        mpid=$(cat "$pid_file" 2>/dev/null)
        [ -n "$mpid" ] && kill "$mpid" 2>/dev/null || true
    fi

    rm -f "$(_xen_domname_file)" "$pty_file" "$pid_file"
    log "INFO" "Xen domain stopped"
}
