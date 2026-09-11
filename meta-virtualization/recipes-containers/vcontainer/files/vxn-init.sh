#!/bin/sh
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: GPL-2.0-only
#
# vxn-init.sh
# Init script for vxn: execute container entrypoint directly in Xen DomU
#
# This script runs on a real filesystem after switch_root from initramfs.
# Unlike vdkr-init.sh which starts Docker, this script directly mounts
# the container's rootfs and executes the entrypoint via chroot.
#
# The VM IS the container — no container runtime runs inside the guest.
#
# Drive layout:
#   /dev/xvda = rootfs.img (this script runs from here, mounted as /)
#   /dev/xvdb = container rootfs (OCI image, passed from host)
#
# Kernel parameters (reuses docker_ prefix for frontend compatibility):
#   docker_cmd=<base64>    Base64-encoded entrypoint command
#   docker_input=<type>    Input type: none, oci, rootfs (default: none)
#   docker_output=<type>   Output type: text (default: text)
#   docker_network=1       Enable networking
#   docker_interactive=1   Interactive mode (suppress boot messages)
#   docker_daemon=1        Daemon mode (command loop on hvc0 via serial PTY)
#   docker_exit_grace=<s>  Grace period (seconds) after entrypoint exits [default: 300]
#
# Version: 1.2.0

# Set runtime-specific parameters before sourcing common code
VCONTAINER_RUNTIME_NAME="vxn"
VCONTAINER_RUNTIME_CMD="chroot"
VCONTAINER_RUNTIME_PREFIX="docker"
VCONTAINER_STATE_DIR="/var/lib/vxn"
VCONTAINER_SHARE_NAME="vxn_share"
VCONTAINER_VERSION="1.2.0"

# Source common init functions
. /vcontainer-init-common.sh

# Drop console_loglevel (and its minimum) to 0 so even KERN_EMERG stays off the
# console. `dmesg -n N` cannot reach 0 -- klogctl clamps at
# minimum_console_loglevel (>=1), so the kernel's "reboot: Restarting system."
# banner (KERN_EMERG, level 0) still leaks through `dmesg -n 1`. A direct write
# to /proc/sys/kernel/printk is not clamped.
_quiet_console() {
    echo "0 4 0 7" > /proc/sys/kernel/printk 2>/dev/null || true
}

# Reboot the DomU quietly. The guest reboots to signal container completion to
# the host; suppress the kernel reboot banner and busybox's own "Rebooting."
# Nothing useful prints after this.
_quiet_reboot() {
    _quiet_console
    reboot -f 2>/dev/null
}

# ============================================================================
# Container Rootfs Handling
# ============================================================================

# Find the container rootfs directory from the input disk.
# Sets CONTAINER_ROOT to the path of the extracted rootfs.
# Install dom0-provided corporate CA cert(s) into the container's trust store.
# dom0 staged them at /mnt/input/.vxn-ca (see vrunner-backend-xen.sh). Appends
# to the existing CA bundle so it works even in minimal containers without
# ca-certificates tooling (no re-bundle), and also drops them into
# /usr/local/share/ca-certificates for containers that do re-bundle. Lets a
# container that does its own TLS/network ops trust a corporate proxy CA.
install_domu_ca_certs() {
    [ -n "$CONTAINER_ROOT" ] || return 0
    ls /mnt/input/.vxn-ca/*.crt >/dev/null 2>&1 || return 0

    local bundle="$CONTAINER_ROOT/etc/ssl/certs/ca-certificates.crt"
    local n=0 f
    mkdir -p "$CONTAINER_ROOT/usr/local/share/ca-certificates" \
             "$CONTAINER_ROOT/etc/ssl/certs" 2>/dev/null
    for f in /mnt/input/.vxn-ca/*.crt; do
        [ -f "$f" ] || continue
        cp "$f" "$CONTAINER_ROOT/usr/local/share/ca-certificates/$(basename "$f")" 2>/dev/null
        cat "$f" >> "$bundle" 2>/dev/null && n=$((n + 1))
    done
    [ "$n" -gt 0 ] && log "Installed $n dom0 CA cert(s) into the container trust store"
}

find_container_rootfs() {
    CONTAINER_ROOT=""

    if [ ! -d /mnt/input ] || [ -z "$(ls -A /mnt/input 2>/dev/null)" ]; then
        log "WARNING: No container rootfs found on input disk"
        return 1
    fi

    # Check if the input disk IS the rootfs (has typical Linux dirs)
    if [ -d /mnt/input/bin ] || [ -d /mnt/input/usr ]; then
        CONTAINER_ROOT="/mnt/input"
        log "Container rootfs: direct mount (/mnt/input)"
    # Check for OCI layout (index.json + blobs/)
    elif [ -f /mnt/input/index.json ] || [ -f /mnt/input/oci-layout ]; then
        log "Found OCI layout on input disk, extracting layers..."
        extract_oci_rootfs /mnt/input /mnt/container
        CONTAINER_ROOT="/mnt/container"
    # Check for rootfs/ subdirectory
    elif [ -d /mnt/input/rootfs ]; then
        CONTAINER_ROOT="/mnt/input/rootfs"
        log "Container rootfs: /mnt/input/rootfs"
    else
        log "WARNING: Could not determine rootfs layout in /mnt/input"
        [ "$QUIET_BOOT" = "0" ] && ls -la /mnt/input/
        return 1
    fi

    # Container inherits dom0's corporate CA(s), if any were staged.
    install_domu_ca_certs
    return 0
}

# Extract OCI image layers into a flat rootfs.
# Usage: extract_oci_rootfs <oci_dir> <target_dir>
extract_oci_rootfs() {
    local oci_dir="$1"
    local target_dir="$2"

    mkdir -p "$target_dir"

    if [ ! -f "$oci_dir/index.json" ]; then
        log "ERROR: No index.json in OCI layout"
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        local manifest_digest=$(jq -r '.manifests[0].digest' "$oci_dir/index.json")
        local manifest_file="$oci_dir/blobs/${manifest_digest/://}"

        if [ -f "$manifest_file" ]; then
            # Extract layer digests from manifest (in order, bottom to top)
            local layers=$(jq -r '.layers[].digest' "$manifest_file")
            for layer_digest in $layers; do
                local layer_file="$oci_dir/blobs/${layer_digest/://}"
                if [ -f "$layer_file" ]; then
                    log "Extracting layer: ${layer_digest#sha256:}"
                    tar -xf "$layer_file" -C "$target_dir" 2>/dev/null || true
                fi
            done
        fi
    else
        # Fallback: find and extract all blobs that look like tarballs
        log "No jq available, extracting all blob layers..."
        for blob in "$oci_dir"/blobs/sha256/*; do
            if [ -f "$blob" ]; then
                tar -xf "$blob" -C "$target_dir" 2>/dev/null || true
            fi
        done
    fi

    if [ -d "$target_dir/bin" ] || [ -d "$target_dir/usr" ] || [ -f "$target_dir/hello" ]; then
        log "OCI rootfs extracted to $target_dir"
        return 0
    else
        log "WARNING: Extracted OCI rootfs may be incomplete"
        [ "$QUIET_BOOT" = "0" ] && ls -la "$target_dir/"
        return 0
    fi
}

# Parse OCI config for environment, entrypoint, cmd, workdir.
# Sets: OCI_ENTRYPOINT, OCI_CMD, OCI_ENV, OCI_WORKDIR
parse_oci_config() {
    OCI_ENTRYPOINT=""
    OCI_CMD=""
    OCI_ENV=""
    OCI_WORKDIR=""

    local config_file=""

    # Look for config in OCI layout on input disk
    if [ -f /mnt/input/index.json ]; then
        config_file=$(oci_find_config_blob /mnt/input)
    fi

    # Check for standalone config.json
    [ -z "$config_file" ] && [ -f /mnt/input/config.json ] && config_file="/mnt/input/config.json"

    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        log "No OCI config found (using command from kernel cmdline)"
        return
    fi

    log "Parsing OCI config: $config_file"

    if command -v jq >/dev/null 2>&1; then
        OCI_ENTRYPOINT=$(jq -r '(.config.Entrypoint // []) | join(" ")' "$config_file" 2>/dev/null)
        OCI_CMD=$(jq -r '(.config.Cmd // []) | join(" ")' "$config_file" 2>/dev/null)
        OCI_WORKDIR=$(jq -r '.config.WorkingDir // ""' "$config_file" 2>/dev/null)
        OCI_ENV=$(jq -r '(.config.Env // []) | .[]' "$config_file" 2>/dev/null)
    else
        # Fallback: parse OCI config JSON with grep/sed (no jq in minimal rootfs)
        log "Using grep/sed fallback for OCI config parsing"
        OCI_ENTRYPOINT=$(oci_grep_json_array "Entrypoint" "$config_file")
        OCI_CMD=$(oci_grep_json_array "Cmd" "$config_file")
        OCI_WORKDIR=$(grep -o '"WorkingDir":"[^"]*"' "$config_file" 2>/dev/null | sed 's/"WorkingDir":"//;s/"$//')
        OCI_ENV=$(grep -o '"Env":\[[^]]*\]' "$config_file" 2>/dev/null | \
            sed 's/"Env":\[//;s/\]$//' | tr ',' '\n' | sed 's/^ *"//;s/"$//')
    fi

    log "OCI config: entrypoint='$OCI_ENTRYPOINT' cmd='$OCI_CMD' workdir='$OCI_WORKDIR'"
}

# Follow OCI index.json → manifest → config blob using grep/sed.
# Works with or without jq.
oci_find_config_blob() {
    local oci_dir="$1"
    local digest=""
    local blob_file=""

    if command -v jq >/dev/null 2>&1; then
        digest=$(jq -r '.manifests[0].digest' "$oci_dir/index.json" 2>/dev/null)
        blob_file="$oci_dir/blobs/${digest/://}"
        [ -f "$blob_file" ] && digest=$(jq -r '.config.digest' "$blob_file" 2>/dev/null)
        blob_file="$oci_dir/blobs/${digest/://}"
    else
        # grep fallback: extract first digest from index.json
        digest=$(grep -o '"digest":"sha256:[a-f0-9]*"' "$oci_dir/index.json" 2>/dev/null | \
            head -n 1 | sed 's/"digest":"//;s/"$//')
        blob_file="$oci_dir/blobs/${digest/://}"
        if [ -f "$blob_file" ]; then
            # Extract config digest from manifest (mediaType contains "config")
            digest=$(grep -o '"config":{[^}]*}' "$blob_file" 2>/dev/null | \
                grep -o '"digest":"sha256:[a-f0-9]*"' | sed 's/"digest":"//;s/"$//')
            blob_file="$oci_dir/blobs/${digest/://}"
        fi
    fi

    [ -f "$blob_file" ] && echo "$blob_file"
}

# Extract a JSON array value as a space-separated string using grep/sed.
# Usage: oci_grep_json_array "Entrypoint" config_file
# Handles: "Entrypoint":["/hello"], "Cmd":["/bin/sh","-c","echo hi"]
oci_grep_json_array() {
    local key="$1"
    local file="$2"
    grep -o "\"$key\":\\[[^]]*\\]" "$file" 2>/dev/null | \
        sed "s/\"$key\":\\[//;s/\\]$//" | \
        tr ',' '\n' | sed 's/^ *"//;s/"$//' | tr '\n' ' ' | sed 's/ $//'
}

# ============================================================================
# Command Resolution
# ============================================================================

# Parse a "docker run" command to extract the container command (after image name).
# "docker run --rm hello-world" → "" (no cmd, use OCI defaults)
# "docker run --rm hello-world /bin/sh" → "/bin/sh"
parse_docker_run_cmd() {
    local full_cmd="$1"
    local found_image=false
    local container_cmd=""
    local skip_next=false

    # Strip "docker run" or "podman run" prefix
    local args=$(echo "$full_cmd" | sed 's/^[a-z]* run //')

    for arg in $args; do
        if [ "$found_image" = "true" ]; then
            container_cmd="$container_cmd $arg"
            continue
        fi

        if [ "$skip_next" = "true" ]; then
            skip_next=false
            continue
        fi

        case "$arg" in
            --rm|--detach|-d|-i|--interactive|-t|--tty|--privileged)
                ;;
            -p|--publish|-v|--volume|-e|--env|--name|--network|-w|--workdir|--entrypoint|-m|--memory|--cpus)
                skip_next=true
                ;;
            -p=*|--publish=*|-v=*|--volume=*|-e=*|--env=*|--name=*|--network=*|-w=*|--workdir=*|--entrypoint=*)
                ;;
            -*)
                ;;
            *)
                # First non-option argument is the image name — skip it
                found_image=true
                ;;
        esac
    done

    echo "$container_cmd" | sed 's/^ *//'
}

# Determine the command to execute inside the container.
# Priority: 1) explicit command from docker run args, 2) RUNTIME_CMD as raw command,
#           3) OCI entrypoint + cmd, 4) /bin/sh fallback
determine_exec_command() {
    local cmd=""

    if [ -n "$RUNTIME_CMD" ]; then
        # Check if this is a "docker run" wrapper command
        if echo "$RUNTIME_CMD" | grep -qE '^(docker|podman) run '; then
            cmd=$(parse_docker_run_cmd "$RUNTIME_CMD")
            # If no command after image name, fall through to OCI config
        else
            # Raw command — use as-is
            cmd="$RUNTIME_CMD"
        fi
    fi

    # If no explicit command, use OCI config
    if [ -z "$cmd" ]; then
        if [ -n "$OCI_ENTRYPOINT" ]; then
            cmd="$OCI_ENTRYPOINT"
            [ -n "$OCI_CMD" ] && cmd="$cmd $OCI_CMD"
        elif [ -n "$OCI_CMD" ]; then
            cmd="$OCI_CMD"
        fi
    fi

    # Final fallback
    if [ -z "$cmd" ]; then
        cmd="/bin/sh"
        log "No command specified, defaulting to /bin/sh"
    fi

    echo "$cmd"
}

# ============================================================================
# Container Execution
# ============================================================================

# Set up environment variables for the container
setup_container_env() {
    # Apply OCI environment variables (incl. the image's PATH). Feed the list
    # via a here-doc, NOT a pipe: `echo | while` runs the loop in a subshell, so
    # the exports would be lost and the entrypoint would run with the init's
    # minimal PATH -- e.g. a node image's `claude` in /usr/local/bin becomes
    # 'exec: claude: not found'. A here-doc keeps the loop in the current shell.
    if [ -n "$OCI_ENV" ]; then
        while IFS= read -r env_line; do
            [ -n "$env_line" ] && export "$env_line" 2>/dev/null || true
        done <<OCIENVEOF
$OCI_ENV
OCIENVEOF
    fi

    # Per-run env from the host (#20): dom0 staged it on the input disk
    # (.vxn-env/env, off any kernel cmdline). KEY=VAL lines -- export each into
    # the container's environment so the entrypoint (e.g. claude) sees them.
    # SKIP container-owned filesystem vars: a vxn DomU has its OWN rootfs, so the
    # host's PATH/HOME/SHELL/etc. are wrong and must not clobber the image's (that
    # would break binary lookup, e.g. `claude` in /usr/local/bin). Provider/agent
    # vars (ANTHROPIC_*, and anything forwarded via VXN_FORWARD_ENV) pass through.
    if [ -f /mnt/input/.vxn-env/env ]; then
        while IFS= read -r env_line; do
            case "$env_line" in
                PATH=*|HOME=*|SHELL=*|USER=*|LOGNAME=*|PWD=*|OLDPWD=*|TMPDIR=*|TERM=*|XDG_*=*) continue ;;
            esac
            [ -n "$env_line" ] && export "$env_line" 2>/dev/null || true
        done < /mnt/input/.vxn-env/env
    fi

    # Ensure a sane PATH even if the image didn't set one.
    case ":${PATH:-}:" in
        *:/usr/local/bin:*) : ;;
        *) export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}" ;;
    esac
    export HOME="${HOME:-/root}"
    export TERM="${TERM:-linux}"
}

# Execute a command inside the container rootfs via chroot.
# Mounts /proc, /sys, /dev inside the container and copies DNS config.
# Nested enforcement (#31, Phase 1): apply cgroup v2 resource limits from the
# policy dom0 staged at /mnt/input/.vxn-policy/policy, as defense-in-depth INSIDE
# the guest (behind the VM boundary). Sets VXN_CGEXEC to a wrapper that drops the
# entrypoint into the limited cgroup right before chroot; leaves it as plain
# `chroot` when there are no limits, so the no-policy path is unchanged. Requested
# limits that can't be enforced are logged loudly, never silently dropped -- the
# VM boundary still holds, but the operator must know the fine-grained cap didn't.
setup_nested_enforcement() {
    VXN_CGEXEC="chroot"
    VXN_CGROUP_DIR=""
    export VXN_CGROUP_DIR
    local pol="/mnt/input/.vxn-policy/policy"
    [ -f "$pol" ] || return 0

    local mem_mb="" pids="" cpu_pct=""
    while IFS='=' read -r k v; do
        case "$k" in
            MAX_MEMORY_MB) mem_mb="$v" ;;
            MAX_PIDS) pids="$v" ;;
            CPU_RATE_PERCENT) cpu_pct="$v" ;;
        esac
    done < "$pol"
    [ -n "$mem_mb$pids$cpu_pct" ] || return 0

    # cgroup v2 unified hierarchy required (setup_cgroups mounts it at
    # /sys/fs/cgroup). If it isn't there, the requested limits can't be enforced.
    if [ ! -f /sys/fs/cgroup/cgroup.controllers ]; then
        log "WARNING: policy requests resource limits but cgroup v2 is unavailable; running UNCONFINED within the VM"
        return 0
    fi

    # Enable the controllers we need on the root's children.
    local avail want=""
    avail=$(cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null)
    case " $avail " in *" memory "*) [ -n "$mem_mb" ] && want="$want +memory" ;; esac
    case " $avail " in *" pids "*)   [ -n "$pids" ]   && want="$want +pids"   ;; esac
    case " $avail " in *" cpu "*)    [ -n "$cpu_pct" ] && want="$want +cpu"   ;; esac
    [ -n "$want" ] && echo $want > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null

    local cg=/sys/fs/cgroup/vxn-agent
    if ! mkdir -p "$cg" 2>/dev/null; then
        log "WARNING: could not create the enforcement cgroup; running UNCONFINED within the VM"
        return 0
    fi

    # memory.max (bytes), pids.max (count), cpu.max ("<quota_us> <period_us>").
    local applied=""
    if [ -n "$mem_mb" ] && [ -w "$cg/memory.max" ]; then
        echo $((mem_mb * 1024 * 1024)) > "$cg/memory.max" 2>/dev/null && applied="$applied mem=${mem_mb}MB"
    fi
    if [ -n "$pids" ] && [ -w "$cg/pids.max" ]; then
        echo "$pids" > "$cg/pids.max" 2>/dev/null && applied="$applied pids=$pids"
    fi
    if [ -n "$cpu_pct" ] && [ -w "$cg/cpu.max" ]; then
        local period=100000
        echo "$((period * cpu_pct / 100)) $period" > "$cg/cpu.max" 2>/dev/null && applied="$applied cpu=${cpu_pct}%"
    fi
    if [ -z "$applied" ]; then
        log "WARNING: policy requests resource limits but none could be written (controllers missing?); running UNCONFINED within the VM"
        return 0
    fi

    # Wrapper: move the to-be-exec'd entrypoint into the cgroup right before
    # chroot. It runs in init's namespace (where /sys is visible) and chroot
    # preserves the pid + cgroup membership. VXN_CGROUP_DIR is read from the env.
    VXN_CGROUP_DIR="$cg"; export VXN_CGROUP_DIR
    mkdir -p /run 2>/dev/null
    if cat > /run/vxn-cgexec <<'CGEOF' 2>/dev/null
#!/bin/sh
[ -n "$VXN_CGROUP_DIR" ] && echo $$ > "$VXN_CGROUP_DIR/cgroup.procs" 2>/dev/null
exec chroot "$@"
CGEOF
    then
        chmod +x /run/vxn-cgexec 2>/dev/null
    fi
    if [ -x /run/vxn-cgexec ]; then
        VXN_CGEXEC="/run/vxn-cgexec"
        log "Nested enforcement: cgroup limits applied ($applied )"
    else
        log "WARNING: cgroup limits set but the cgexec wrapper is unavailable; the entrypoint may not enter the cgroup"
    fi
}

# Nested enforcement (#31, Phase 2): apply the AXIS filesystem policy as a
# bind-mount view on the container rootfs BEFORE chroot, as defense-in-depth.
#   RO=<path>   -> remount that subtree read-only
#   RW=<path>   -> remount read-write (carve-out that wins over a broader RO)
#   DENY=<path> -> over-mount (empty tmpfs over a dir, /dev/null over a file) so
#                  the original content is inaccessible
# CAVEAT: bind-mount ro/deny is best-effort against a NON-privileged agent. A
# root agent with CAP_SYS_ADMIN can remount rw / umount to escape it UNTIL
# Phase 3's seccomp denies the mount/umount syscalls -- that is the intended
# layering (Phase 2 builds the view, Phase 3 locks it). Requests that cannot be
# enforced are logged, never silently dropped.
apply_fs_policy() {
    local rootfs="$1"
    local pol="/mnt/input/.vxn-policy/policy"
    [ -f "$pol" ] || return 0
    grep -qE '^(RO|RW|DENY)=' "$pol" 2>/dev/null || return 0

    local applied=0 kind path tgt
    # Pass 1: RO. Bind onto self first so remount,ro,bind scopes to this subtree.
    while IFS='=' read -r kind path; do
        [ "$kind" = "RO" ] || continue
        tgt="$rootfs$path"
        [ -e "$tgt" ] || { log "fs-policy: RO target missing, skip: $path"; continue; }
        if mount -o bind "$tgt" "$tgt" 2>/dev/null && mount -o remount,ro,bind "$tgt" 2>/dev/null; then
            applied=$((applied + 1))
        else
            log "WARNING: fs-policy could not make read-only: $path"
        fi
    done < "$pol"

    # Pass 2: RW carve-outs (win over any broader RO applied above).
    while IFS='=' read -r kind path; do
        [ "$kind" = "RW" ] || continue
        tgt="$rootfs$path"
        [ -e "$tgt" ] || { log "fs-policy: RW target missing, skip: $path"; continue; }
        mount -o bind "$tgt" "$tgt" 2>/dev/null
        mount -o remount,rw,bind "$tgt" 2>/dev/null && applied=$((applied + 1))
    done < "$pol"

    # Pass 3: DENY (hide + block). Empty ro tmpfs over dirs; /dev/null over files.
    while IFS='=' read -r kind path; do
        [ "$kind" = "DENY" ] || continue
        tgt="$rootfs$path"
        [ -e "$tgt" ] || { log "fs-policy: DENY target missing, skip: $path"; continue; }
        if [ -d "$tgt" ]; then
            mount -t tmpfs -o ro,nosuid,nodev,mode=000 vxn-deny "$tgt" 2>/dev/null \
                && applied=$((applied + 1)) || log "WARNING: fs-policy could not deny dir: $path"
        else
            mount -o bind /dev/null "$tgt" 2>/dev/null \
                && applied=$((applied + 1)) || log "WARNING: fs-policy could not deny file: $path"
        fi
    done < "$pol"

    [ "$applied" -gt 0 ] && log "Nested enforcement: filesystem policy applied ($applied mount(s))"
}

exec_in_container() {
    local rootfs="$1"
    local cmd="$2"
    local workdir="${OCI_WORKDIR:-/}"

    # Mount essential filesystems inside the container rootfs
    mkdir -p "$rootfs/proc" "$rootfs/sys" "$rootfs/dev" "$rootfs/tmp" 2>/dev/null || true
    mount -t proc proc "$rootfs/proc" 2>/dev/null || true
    mount -t sysfs sysfs "$rootfs/sys" 2>/dev/null || true
    mount --bind /dev "$rootfs/dev" 2>/dev/null || true

    # Copy resolv.conf for DNS
    if [ -f /etc/resolv.conf ]; then
        mkdir -p "$rootfs/etc" 2>/dev/null || true
        cp /etc/resolv.conf "$rootfs/etc/resolv.conf" 2>/dev/null || true
    fi

    log "Executing in container: $cmd"
    log "Working directory: $workdir"

    # Determine how to exec: use /bin/sh if available, otherwise direct exec
    local use_sh=true
    if [ ! -x "$rootfs/bin/sh" ]; then
        use_sh=false
        log "No /bin/sh in container, using direct exec"
    fi

    # Opaque argv (#31): the command may be a single sentinel token
    #   __VXNARGV__<base64(arg0)>,<base64(arg1)>,...
    # carrying the container argv as a space-free, metacharacter-free unit that
    # survives the string dispatch (no flag-eating: no '-' prefix; no shell
    # mangling: no spaces/metachars in transit). Decode it back into the
    # positional parameters and exec the VECTOR verbatim below -- passed as "$@"
    # to a fixed `exec "$@"` script, so an arbitrary command (quotes, parens, $)
    # is never re-lexed by a shell. `set --` is safe here: rootfs/cmd/workdir are
    # already saved in locals.
    local _vxn_argv_mode=0 _tok _oifs
    case "$cmd" in
        __VXNARGV__*)
            _vxn_argv_mode=1
            set --
            _oifs="$IFS"; IFS=,
            for _tok in ${cmd#__VXNARGV__}; do
                set -- "$@" "$(printf '%s' "$_tok" | base64 -d)"
            done
            IFS="$_oifs"
            log "Container argv: $# element(s), exec'd verbatim (no shell re-parse)"
            ;;
    esac

    # Nested enforcement (#31): apply cgroup resource limits from the staged
    # policy and select the cgroup-entering chroot wrapper (VXN_CGEXEC). No-op
    # (VXN_CGEXEC=chroot) when no policy was staged.
    setup_nested_enforcement
    # Phase 2: apply the filesystem policy as a bind-mount view on the rootfs
    # (after /proc,/sys,/dev are mounted above, before chroot). No-op if none.
    apply_fs_policy "$rootfs"

    if [ "$RUNTIME_INTERACTIVE" = "1" ]; then
        # Interactive mode: establish a controlling terminal for job control.
        # PID 1 is already a session leader, so setsid() would fork — run in
        # a subshell (not session leader) where setsid() succeeds directly.
        # The -c flag does ioctl(TIOCSCTTY) on stdin to set the controlling tty.
        # TERM: the console is a byte pass-through (hvc0 -> xl console -> dom0 pty
        # -> ssh -> the user's REAL terminal, which does the rendering), so a rich
        # TERM is correct here -- `linux` crippled TUIs like claude's Ink UI to
        # basic escapes. Override with VXN_TERM if a target terminal differs.
        export TERM="${VXN_TERM:-xterm-256color}"
        # Set the controlling tty geometry to the dom0 terminal's size before
        # exec. winsize is a property of the tty device (hvc0 = our stdin), so
        # claude inherits it across chroot/exec -- including the direct-exec
        # argv path, which has no shell wrapper to run stty itself. Without this
        # the guest tty is 80x25 and the TUI renders clipped. (Live resize is
        # the hvc1 side-channel follow-up; this fixes the initial geometry.)
        if [ -n "$VXN_WIN_ROWS" ] && [ -n "$VXN_WIN_COLS" ]; then
            stty rows "$VXN_WIN_ROWS" cols "$VXN_WIN_COLS" 2>/dev/null || true
        fi
        # Quiet the guest console for the whole interactive session: drop it to
        # 0 (not `dmesg -n 1`, which leaves KERN_EMERG visible) so the "reboot:
        # Restarting system." banner from graceful_shutdown below never reaches
        # the user's terminal interleaved with the agent's UI.
        _quiet_console
        if [ "$_vxn_argv_mode" = "1" ]; then
            # argv rides as positional params, never re-lexed
            (exec setsid -c $VXN_CGEXEC "$rootfs" /bin/sh -c 'cd "$1" 2>/dev/null; shift; exec "$@"' _ "$workdir" "$@")
        elif [ "$use_sh" = "true" ]; then
            (exec setsid -c $VXN_CGEXEC "$rootfs" /bin/sh -c "cd '$workdir' 2>/dev/null; exec $cmd")
        else
            (exec setsid -c $VXN_CGEXEC "$rootfs" $cmd)
        fi
        EXEC_EXIT_CODE=$?
    else
        # Non-interactive: capture output
        EXEC_OUTPUT="/tmp/container_output.txt"
        EXEC_EXIT_CODE=0
        if [ "$_vxn_argv_mode" = "1" ]; then
            # argv rides as positional params, never re-lexed
            $VXN_CGEXEC "$rootfs" /bin/sh -c 'cd "$1" 2>/dev/null; shift; exec "$@"' _ "$workdir" "$@" \
                > "$EXEC_OUTPUT" 2>&1 || EXEC_EXIT_CODE=$?
        elif [ "$use_sh" = "true" ]; then
            $VXN_CGEXEC "$rootfs" /bin/sh -c "cd '$workdir' 2>/dev/null; $cmd" \
                > "$EXEC_OUTPUT" 2>&1 || EXEC_EXIT_CODE=$?
        else
            $VXN_CGEXEC "$rootfs" $cmd \
                > "$EXEC_OUTPUT" 2>&1 || EXEC_EXIT_CODE=$?
        fi

        log "Exit code: $EXEC_EXIT_CODE"

        echo "===OUTPUT_START==="
        # Boot-flow timing (vcontainer_timing): print the collected stamps inside
        # the captured OUTPUT so they reach the user's terminal directly (the
        # runner only surfaces this region; pre-boot console goes to a temp file
        # that a plain `vxn run` cleans up).
        [ "$_VXN_TIMING" = "1" ] && [ -f /vxntiming ] && cat /vxntiming
        cat "$EXEC_OUTPUT"
        echo "===OUTPUT_END==="
        echo "===EXIT_CODE=$EXEC_EXIT_CODE==="
    fi

    # Cleanup mounts inside container
    umount "$rootfs/proc" 2>/dev/null || true
    umount "$rootfs/sys" 2>/dev/null || true
    umount "$rootfs/dev" 2>/dev/null || true
}

# Execute a command inside the container rootfs in the background.
# Used by detached mode: start entrypoint, then enter daemon loop.
#
# The entrypoint and its exit-code monitor run in a single background
# subshell so that busybox ash's wait(1) can retrieve the exit status.
# ash can only wait for direct children — starting the chroot in the
# parent shell and waiting in a sibling subshell returns 127 immediately
# (POSIX: "behavior is unspecified" for non-children).
exec_in_container_background() {
    local rootfs="$1"
    local cmd="$2"
    local workdir="${OCI_WORKDIR:-/}"

    # Mount essential filesystems inside the container rootfs (synchronous —
    # daemon loop exec path needs these mounts immediately)
    mkdir -p "$rootfs/proc" "$rootfs/sys" "$rootfs/dev" "$rootfs/tmp" 2>/dev/null || true
    mount -t proc proc "$rootfs/proc" 2>/dev/null || true
    mount -t sysfs sysfs "$rootfs/sys" 2>/dev/null || true
    mount --bind /dev "$rootfs/dev" 2>/dev/null || true

    # Copy resolv.conf for DNS
    if [ -f /etc/resolv.conf ]; then
        mkdir -p "$rootfs/etc" 2>/dev/null || true
        cp /etc/resolv.conf "$rootfs/etc/resolv.conf" 2>/dev/null || true
    fi

    # Start entrypoint + exit-code monitor as a single background subshell.
    # The chroot process is a direct child of this subshell, so wait works.
    (
        chroot "$rootfs" /bin/sh -c "cd '$workdir' 2>/dev/null; $cmd" \
            > /tmp/entrypoint.log 2>&1 &
        EP_PID=$!
        echo "$EP_PID" > /tmp/entrypoint.pid
        log "Entrypoint PID: $EP_PID"

        wait $EP_PID 2>/dev/null
        EP_EXIT=$?
        echo "$EP_EXIT" > /tmp/entrypoint.exit_code
        log "Entrypoint exited (code: $EP_EXIT), grace period: ${ENTRYPOINT_GRACE_PERIOD}s"
        if [ "$ENTRYPOINT_GRACE_PERIOD" -gt 0 ] 2>/dev/null; then
            sleep "$ENTRYPOINT_GRACE_PERIOD"
        fi
        log "Grace period expired, shutting down"
        _quiet_reboot
    ) &
    ENTRYPOINT_MONITOR_PID=$!
    log "Entrypoint monitor started (PID: $ENTRYPOINT_MONITOR_PID)"
}

# ============================================================================
# Memres: Run Container from Hot-Plugged Disk
# ============================================================================

# Run a container from a hot-plugged /dev/xvdb block device.
# Called by the daemon loop in response to ===RUN_CONTAINER=== command.
# Mounts the device, finds rootfs, executes entrypoint, unmounts.
# Output follows the daemon command protocol (===OUTPUT_START/END/EXIT_CODE/END===).
run_container_from_disk() {
    local user_cmd="$1"

    # Wait for hot-plugged block device
    log "Waiting for input device..."
    local found=false
    for i in $(seq 1 30); do
        if [ -b /dev/xvdb ]; then
            found=true
            break
        fi
        sleep 0.5
    done

    if [ "$found" != "true" ]; then
        echo "===ERROR==="
        echo "Input device /dev/xvdb not found after 15s"
        echo "===END==="
        return
    fi

    # Mount input disk
    mkdir -p /mnt/input
    if ! mount /dev/xvdb /mnt/input >/dev/null 2>&1; then
        echo "===ERROR==="
        echo "Failed to mount /dev/xvdb"
        echo "===END==="
        return
    fi
    log "Input disk mounted"

    # Find container rootfs
    if ! find_container_rootfs; then
        echo "===ERROR==="
        echo "No container rootfs found on input disk"
        echo "===END==="
        umount /mnt/input 2>/dev/null || true
        return
    fi

    # Parse OCI config for entrypoint/env/workdir
    parse_oci_config
    setup_container_env

    # Determine command: user-supplied takes priority, then OCI config
    if [ -n "$user_cmd" ]; then
        RUNTIME_CMD="$user_cmd"
    else
        RUNTIME_CMD=""
    fi
    local exec_cmd
    exec_cmd=$(determine_exec_command)

    log "Executing container: $exec_cmd"

    # Execute in container rootfs (blocking)
    local rootfs="$CONTAINER_ROOT"
    local workdir="${OCI_WORKDIR:-/}"
    local exit_code=0

    # Mount essential filesystems inside container
    mkdir -p "$rootfs/proc" "$rootfs/sys" "$rootfs/dev" "$rootfs/tmp" 2>/dev/null || true
    mount -t proc proc "$rootfs/proc" 2>/dev/null || true
    mount -t sysfs sysfs "$rootfs/sys" 2>/dev/null || true
    mount --bind /dev "$rootfs/dev" 2>/dev/null || true
    [ -f /etc/resolv.conf ] && {
        mkdir -p "$rootfs/etc" 2>/dev/null || true
        cp /etc/resolv.conf "$rootfs/etc/resolv.conf" 2>/dev/null || true
    }

    local output_file="/tmp/container_run_output.txt"
    if [ -x "$rootfs/bin/sh" ]; then
        chroot "$rootfs" /bin/sh -c "cd '$workdir' 2>/dev/null; $exec_cmd" \
            > "$output_file" 2>&1 || exit_code=$?
    else
        chroot "$rootfs" $exec_cmd \
            > "$output_file" 2>&1 || exit_code=$?
    fi

    echo "===OUTPUT_START==="
    cat "$output_file"
    echo "===OUTPUT_END==="
    echo "===EXIT_CODE=$exit_code==="

    # Clean up container mounts
    umount "$rootfs/proc" 2>/dev/null || true
    umount "$rootfs/sys" 2>/dev/null || true
    umount "$rootfs/dev" 2>/dev/null || true
    umount /mnt/input 2>/dev/null || true
    rm -f "$output_file"

    # Reset container state for next run
    CONTAINER_ROOT=""
    OCI_ENTRYPOINT=""
    OCI_CMD=""
    OCI_ENV=""
    OCI_WORKDIR=""
    RUNTIME_CMD=""
    # Clean up extracted OCI rootfs (if any)
    rm -rf /mnt/container 2>/dev/null || true

    echo "===END==="
    log "Container finished (exit code: $exit_code)"
}

# ============================================================================
# Daemon Mode (vxn-specific)
# ============================================================================

# Daemon mode: command loop on hvc0 (stdin/stdout).
# The host bridges the domain's console PTY to a Unix socket via socat.
# Commands arrive as base64-encoded lines on stdin, responses go to stdout.
# This is the same model runx used (serial='pty' + serial_start).
run_vxn_daemon_mode() {
    log "=== vxn Daemon Mode ==="
    log "Container rootfs: ${CONTAINER_ROOT:-(none)}"
    log "Idle timeout: ${RUNTIME_IDLE_TIMEOUT}s"

    ACTIVITY_FILE="/tmp/.daemon_activity"
    touch "$ACTIVITY_FILE"
    DAEMON_PID=$$

    trap 'log "Shutdown signal"; sync; _quiet_reboot' TERM
    trap 'rm -f "$ACTIVITY_FILE"; exit' INT

    log "Using hvc0 console for daemon IPC"
    log "Daemon ready, waiting for commands..."

    # Emit readiness marker so the host can detect daemon is ready
    # without needing to send PING first (host reads PTY for this)
    echo "===PONG==="

    # Command loop: read from stdin (hvc0), write to stdout (hvc0)
    while true; do
        CMD_B64=""
        read -r CMD_B64
        READ_EXIT=$?

        if [ $READ_EXIT -eq 0 ] && [ -n "$CMD_B64" ]; then
            touch "$ACTIVITY_FILE"

            case "$CMD_B64" in
                "===PING===")
                    echo "===PONG==="
                    continue
                    ;;
                "===STATUS===")
                    if [ -f /tmp/entrypoint.exit_code ]; then
                        echo "===EXITED=$(cat /tmp/entrypoint.exit_code)==="
                    else
                        echo "===RUNNING==="
                    fi
                    continue
                    ;;
                "===SHUTDOWN===")
                    log "Received shutdown command"
                    echo "===SHUTTING_DOWN==="
                    break
                    ;;
                "===RUN_CONTAINER==="*)
                    # Memres: run a container from a hot-plugged disk
                    _rc_cmd_b64="${CMD_B64#===RUN_CONTAINER===}"
                    _rc_cmd=""
                    if [ -n "$_rc_cmd_b64" ]; then
                        _rc_cmd=$(echo "$_rc_cmd_b64" | base64 -d 2>/dev/null)
                    fi
                    log "RUN_CONTAINER: cmd='$_rc_cmd'"
                    run_container_from_disk "$_rc_cmd"
                    continue
                    ;;
            esac

            # Decode command
            CMD=$(echo "$CMD_B64" | base64 -d 2>/dev/null)
            if [ -z "$CMD" ]; then
                echo "===ERROR==="
                echo "Failed to decode command"
                echo "===END==="
                continue
            fi

            log "Executing: $CMD"

            # Execute command in container rootfs (or host rootfs if no container)
            EXEC_OUTPUT="/tmp/daemon_output.txt"
            EXEC_EXIT_CODE=0
            if [ -n "$CONTAINER_ROOT" ]; then
                chroot "$CONTAINER_ROOT" /bin/sh -c "$CMD" \
                    > "$EXEC_OUTPUT" 2>&1 || EXEC_EXIT_CODE=$?
            else
                eval "$CMD" > "$EXEC_OUTPUT" 2>&1 || EXEC_EXIT_CODE=$?
            fi

            echo "===OUTPUT_START==="
            cat "$EXEC_OUTPUT"
            echo "===OUTPUT_END==="
            echo "===EXIT_CODE=$EXEC_EXIT_CODE==="
            echo "===END==="

            log "Command completed (exit code: $EXEC_EXIT_CODE)"
        else
            sleep 0.1
        fi
    done

    log "Daemon shutting down..."
}

# ============================================================================
# Main
# ============================================================================

# Initialize base environment
setup_base_environment
mount_base_filesystems

# Check for quiet boot mode
check_quiet_boot

# Interactive mode: suppress guest kernel console messages early
if [ "$QUIET_BOOT" = "1" ]; then
    dmesg -n 1 2>/dev/null || true
fi

# Boot-flow timing (opt-in via `vcontainer_timing` on the kernel cmdline).
# Continues the stamps from vcontainer-preinit.sh; userspace echoes land in the
# runner's captured vm_output.txt (`vxn run --keep-temp`, grep VXNTIME). init:start
# vs preinit:switch_root shows the initramfs->real-init handoff; later deltas show
# where the vxn-init sequence spends time.
_VXN_TIMING=0
case " $(cat /proc/cmdline 2>/dev/null) " in *" vcontainer_timing"*) _VXN_TIMING=1 ;; esac
# Append init stamps to /run/vxntiming (preinit already seeded it before
# switch_root); exec_in_container prints the file inside the OUTPUT markers.
_ts() { [ "$_VXN_TIMING" = "1" ] && { echo "VXNTIME init:$1 $(cut -d' ' -f1 /proc/uptime)" >> /vxntiming; }; }
_ts start

log "=== vxn Init ==="
log "Version: $VCONTAINER_VERSION"

# Mount tmpfs directories and cgroups
mount_tmpfs_dirs
setup_cgroups

# Parse kernel command line
parse_cmdline
_ts cmdline

# Parse vxn-specific kernel parameters
ENTRYPOINT_GRACE_PERIOD="300"
# Window size captured on dom0 at launch (see hv_start_vm_foreground). hvc0 /
# xl console never relay the terminal winsize into the guest, so without this
# the guest tty stays at the kernel default 80x25 and full-screen TUIs render
# clipped. Applied in exec_in_container's interactive branch before exec.
VXN_WIN_ROWS=""
VXN_WIN_COLS=""
for param in $(cat /proc/cmdline); do
    case "$param" in
        docker_exit_grace=*) ENTRYPOINT_GRACE_PERIOD="${param#docker_exit_grace=}" ;;
        vcontainer.rows=*) VXN_WIN_ROWS="${param#vcontainer.rows=}" ;;
        vcontainer.cols=*) VXN_WIN_COLS="${param#vcontainer.cols=}" ;;
    esac
done
log "Entrypoint grace period: ${ENTRYPOINT_GRACE_PERIOD}s"

# Detect and configure disks
detect_disks

# Mount input disk (container rootfs from host)
mount_input_disk
_ts disks

# Configure networking
configure_networking
_ts net

# Find the container rootfs on the input disk
if ! find_container_rootfs; then
    if [ "$RUNTIME_DAEMON" = "1" ]; then
        log "No container rootfs, daemon mode will execute on host rootfs"
        CONTAINER_ROOT=""
    else
        echo "===ERROR==="
        echo "No container rootfs found on input disk"
        echo "Contents of /mnt/input:"
        ls -la /mnt/input/ 2>/dev/null || echo "(empty)"
        sleep 2
        _quiet_reboot
    fi
fi

# Parse OCI config for entrypoint/env/workdir
parse_oci_config
_ts rootfs

# Set up container environment
setup_container_env

if [ "$RUNTIME_DAEMON" = "1" ]; then
    # If we also have a command, run it in background first (detached container)
    if [ -n "$RUNTIME_CMD" ] && [ "$RUNTIME_CMD" != "1" ]; then
        EXEC_CMD=$(determine_exec_command)
        if [ -n "$EXEC_CMD" ] && [ -n "$CONTAINER_ROOT" ]; then
            log "Starting entrypoint in background: $EXEC_CMD"
            exec_in_container_background "$CONTAINER_ROOT" "$EXEC_CMD"
        fi
    fi
    run_vxn_daemon_mode
else
    # Determine command to execute
    EXEC_CMD=$(determine_exec_command)

    if [ -z "$EXEC_CMD" ]; then
        echo "===ERROR==="
        echo "No command to execute"
        sleep 2
        _quiet_reboot
    fi

    # Execute in container rootfs
    _ts preexec
    exec_in_container "$CONTAINER_ROOT" "$EXEC_CMD"
fi

# Graceful shutdown
graceful_shutdown
