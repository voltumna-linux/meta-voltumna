# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# container-registry-index.bb
# ===========================================================================
# Push OCI container images to a registry (like package-index for containers)
# ===========================================================================
#
# This is the container equivalent of meta/recipes-core/meta/package-index.bb
# It discovers OCI images in DEPLOY_DIR_IMAGE and pushes them to a registry.
#
# Usage:
#   # Start registry first (separate terminal):
#   oe-run-native docker-distribution-native registry serve config.yml
#
#   # Push all container images to registry:
#   bitbake container-registry-index
#
#   # Or use the helper script:
#   oe-run-native container-registry-index
#
# Configuration (in local.conf):
#   CONTAINER_REGISTRY_URL = "localhost:5000"
#   CONTAINER_REGISTRY_NAMESPACE = "yocto"
#   CONTAINER_REGISTRY_IMAGES = "container-base container-app"  # optional filter
#
# ===========================================================================

SUMMARY = "Populate container registry with OCI images"
LICENSE = "MIT"

INHIBIT_DEFAULT_DEPS = "1"
PACKAGES = ""

inherit nopackages container-registry

deltask do_fetch
deltask do_unpack
deltask do_patch
deltask do_configure
deltask do_compile
deltask do_install
deltask do_populate_lic
deltask do_populate_sysroot

do_container_registry_index[nostamp] = "1"
do_container_registry_index[network] = "1"
do_container_registry_index[depends] += "skopeo-native:do_populate_sysroot"

python do_container_registry_index() {
    import os

    registry = d.getVar('CONTAINER_REGISTRY_URL')
    namespace = d.getVar('CONTAINER_REGISTRY_NAMESPACE')
    specific_images = (d.getVar('CONTAINER_REGISTRY_IMAGES') or '').split()

    bb.plain(f"Container Registry Index: {registry}/{namespace}/")

    # Discover OCI images
    all_images = container_registry_discover_oci_images(d)

    if not all_images:
        bb.warn("No OCI images found in deploy directory")
        bb.plain(f"Deploy directory: {d.getVar('DEPLOY_DIR_IMAGE')}")
        bb.plain("Build container images first: bitbake container-base")
        return

    bb.plain(f"Found {len(all_images)} OCI images")

    # Filter if specific images requested
    if specific_images:
        images = [(path, name) for path, name in all_images if name in specific_images]
    else:
        images = all_images

    # Push each image
    pushed_refs = []
    for oci_path, image_name in images:
        bb.plain(f"Pushing: {image_name}")
        refs = container_registry_push(d, oci_path, image_name)
        pushed_refs.extend(refs)

    bb.plain(f"Pushed {len(pushed_refs)} image references to {registry}")
}

addtask do_container_registry_index

python do_build() {
    bb.plain("")
    bb.plain("Container registry push requires explicit invocation (network access")
    bb.plain("is not permitted during the normal build chain).")
    bb.plain("")
    bb.plain("To push OCI images to the registry, run:")
    bb.plain("")
    bb.plain("  bitbake container-registry-index -c container_registry_index")
    bb.plain("")
}

# Generate a helper script with paths baked in
# Script is placed alongside registry storage (outside tmp/) so it persists
CONTAINER_REGISTRY_SCRIPT = "${CONTAINER_REGISTRY_STORAGE}/container-registry.sh"

python do_generate_registry_script() {
    import os
    import stat
    import shutil

    script_path = d.getVar('CONTAINER_REGISTRY_SCRIPT')
    deploy_dir = d.getVar('DEPLOY_DIR')
    deploy_dir_image = d.getVar('DEPLOY_DIR_IMAGE')
    # Parent of DEPLOY_DIR_IMAGE (e.g., tmp/deploy/images/) for multi-arch discovery
    deploy_dir_images = os.path.dirname(deploy_dir_image)

    # Find registry binary path
    native_sysroot = d.getVar('STAGING_DIR_NATIVE') or ''
    registry_bin = os.path.join(native_sysroot, 'usr', 'sbin', 'registry')

    # Find skopeo binary path
    skopeo_bin = os.path.join(d.getVar('STAGING_SBINDIR_NATIVE') or '', 'skopeo')

    # Registry settings
    registry_url = d.getVar('CONTAINER_REGISTRY_URL')
    registry_namespace = d.getVar('CONTAINER_REGISTRY_NAMESPACE')
    registry_storage = d.getVar('CONTAINER_REGISTRY_STORAGE')
    tag_strategy = d.getVar('CONTAINER_REGISTRY_TAG_STRATEGY') or 'latest'
    target_arch = d.getVar('TARGET_ARCH') or ''

    # Secure mode settings
    secure_mode = d.getVar('CONTAINER_REGISTRY_SECURE') or '0'
    auth_enabled = d.getVar('CONTAINER_REGISTRY_AUTH') or '0'
    registry_username = d.getVar('CONTAINER_REGISTRY_USERNAME') or 'yocto'
    ca_days = d.getVar('CONTAINER_REGISTRY_CA_DAYS') or '3650'
    cert_days = d.getVar('CONTAINER_REGISTRY_CERT_DAYS') or '365'
    custom_san = d.getVar('CONTAINER_REGISTRY_CERT_SAN') or ''

    # Create storage directory
    os.makedirs(registry_storage, exist_ok=True)
    os.makedirs(deploy_dir, exist_ok=True)

    # Generate PKI infrastructure for secure mode
    if secure_mode == '1':
        import subprocess

        pki_dir = os.path.join(registry_storage, 'pki')
        auth_dir = os.path.join(registry_storage, 'auth')
        os.makedirs(pki_dir, exist_ok=True)
        os.makedirs(auth_dir, exist_ok=True)

        ca_key = os.path.join(pki_dir, 'ca.key')
        ca_crt = os.path.join(pki_dir, 'ca.crt')
        server_key = os.path.join(pki_dir, 'server.key')
        server_csr = os.path.join(pki_dir, 'server.csr')
        server_crt = os.path.join(pki_dir, 'server.crt')

        # Find openssl from native sysroot
        openssl_bin = os.path.join(native_sysroot, 'usr', 'bin', 'openssl')
        if not os.path.exists(openssl_bin):
            openssl_bin = 'openssl'  # Fall back to system openssl

        # Generate CA if it doesn't exist
        if not os.path.exists(ca_crt):
            bb.plain("Generating PKI infrastructure for secure registry...")

            # Generate CA private key
            subprocess.run([
                openssl_bin, 'genrsa', '-out', ca_key, '4096'
            ], check=True, capture_output=True)
            os.chmod(ca_key, 0o600)

            # Generate CA certificate
            subprocess.run([
                openssl_bin, 'req', '-new', '-x509', '-days', ca_days,
                '-key', ca_key, '-out', ca_crt,
                '-subj', '/CN=Container Registry CA/O=Yocto/C=US'
            ], check=True, capture_output=True)

            bb.plain(f"  Generated CA certificate: {ca_crt}")

        # Generate server cert if it doesn't exist
        if not os.path.exists(server_crt):
            # Build SAN list
            registry_host = registry_url.split(':')[0] if ':' in registry_url else registry_url
            san_entries = [
                'DNS:localhost',
                f'DNS:{registry_host}',
                'IP:127.0.0.1',
                'IP:10.0.2.2'
            ]
            if custom_san:
                san_entries.extend(custom_san.split(','))
            san_string = ','.join(san_entries)

            # Generate server private key
            subprocess.run([
                openssl_bin, 'genrsa', '-out', server_key, '4096'
            ], check=True, capture_output=True)
            os.chmod(server_key, 0o600)

            # Create OpenSSL config for SAN
            openssl_conf = os.path.join(pki_dir, 'openssl.cnf')
            with open(openssl_conf, 'w') as f:
                f.write(f'''[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = {registry_host}
O = Yocto
C = US

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = {san_string}

[v3_ca]
subjectAltName = {san_string}
''')

            # Generate CSR
            subprocess.run([
                openssl_bin, 'req', '-new', '-key', server_key,
                '-out', server_csr, '-config', openssl_conf
            ], check=True, capture_output=True)

            # Sign server cert with CA
            subprocess.run([
                openssl_bin, 'x509', '-req', '-days', cert_days,
                '-in', server_csr, '-CA', ca_crt, '-CAkey', ca_key,
                '-CAcreateserial', '-out', server_crt,
                '-extensions', 'v3_ca', '-extfile', openssl_conf
            ], check=True, capture_output=True)

            bb.plain(f"  Generated server certificate with SAN: {', '.join(san_entries)}")

        bb.plain(f"  PKI directory: {pki_dir}")

    # Copy config file to storage directory and update storage path
    # Use secure config when CONTAINER_REGISTRY_SECURE=1
    if secure_mode == '1':
        src_config = os.path.join(d.getVar('THISDIR'), 'files', 'container-registry-secure.yml')
        if not os.path.exists(src_config):
            bb.warn("Secure mode enabled but container-registry-secure.yml not found, using dev config")
            src_config = os.path.join(d.getVar('THISDIR'), 'files', 'container-registry-dev.yml')
    else:
        src_config = os.path.join(d.getVar('THISDIR'), 'files', 'container-registry-dev.yml')

    config_file = os.path.join(registry_storage, 'registry-config.yml')
    with open(src_config, 'r') as f:
        config_content = f.read()
    # Replace the default storage path with actual path
    config_content = config_content.replace(
        'rootdirectory: /tmp/container-registry',
        f'rootdirectory: {registry_storage}'
    )
    config_content = config_content.replace(
        '__STORAGE_PATH__',
        registry_storage
    )
    config_content = config_content.replace(
        '__PKI_DIR__',
        os.path.join(registry_storage, 'pki')
    )
    config_content = config_content.replace(
        '__AUTH_DIR__',
        os.path.join(registry_storage, 'auth')
    )
    # Remove auth section if AUTH is not enabled (TLS-only mode)
    if secure_mode == '1' and auth_enabled != '1':
        import re
        # Remove the auth block (including htpasswd subsection)
        config_content = re.sub(r'\n# htpasswd authentication\nauth:\n  htpasswd:\n    realm:.*\n    path:.*\n', '\n', config_content)
    with open(config_file, 'w') as f:
        f.write(config_content)

    script = f'''#!/bin/bash
# Container Registry Helper Script
# Generated by: bitbake container-registry-index -c generate_registry_script
#
# This script has all paths pre-configured for your build.
#
# Usage:
#   {script_path} start                     # Start registry server
#   {script_path} stop                      # Stop registry server
#   {script_path} status                    # Check if running
#   {script_path} push [options]            # Push OCI images to registry
#   {script_path} import <image>            # Import 3rd party image
#   {script_path} list                      # List all images with tags
#   {script_path} tags <image>              # List tags for an image
#   {script_path} catalog                   # List image names (raw API)
#
# Push options:
#   --tag <tag>           Explicit tag (can be repeated)
#   --strategy <strats>   Tag strategy: timestamp, sha, branch, semver, latest, arch
#   --version <ver>       Version for semver strategy (e.g., 1.2.3)

set -e

# Pre-configured paths from bitbake (overridable via environment)
REGISTRY_BIN="{registry_bin}"
SKOPEO_BIN="{skopeo_bin}"
REGISTRY_STORAGE="${{CONTAINER_REGISTRY_STORAGE:-{registry_storage}}}"
REGISTRY_URL="${{CONTAINER_REGISTRY_URL:-{registry_url}}}"
REGISTRY_NAMESPACE="${{CONTAINER_REGISTRY_NAMESPACE:-{registry_namespace}}}"
REGISTRY_CONFIG="$REGISTRY_STORAGE/registry-config.yml"

# Deploy directories - can be overridden via environment
# DEPLOY_DIR_IMAGES: parent directory containing per-machine deploy dirs
# DEPLOY_DIR_IMAGE: single machine deploy dir (legacy, still supported)
DEPLOY_DIR_IMAGES="${{DEPLOY_DIR_IMAGES:-{deploy_dir_images}}}"
DEPLOY_DIR_IMAGE="${{DEPLOY_DIR_IMAGE:-{deploy_dir_image}}}"

# Baked-in defaults from bitbake (can be overridden by CLI or env vars)
DEFAULT_TAG_STRATEGY="{tag_strategy}"
DEFAULT_TARGET_ARCH="{target_arch}"

# Authentication settings (can be overridden via CLI options or env vars)
AUTH_MODE="${{CONTAINER_REGISTRY_AUTH_MODE:-none}}"
AUTHFILE="${{CONTAINER_REGISTRY_AUTHFILE:-}}"
CREDSFILE="${{CONTAINER_REGISTRY_CREDSFILE:-}}"

# Secure mode settings (baked from bitbake)
SECURE_MODE="${{CONTAINER_REGISTRY_SECURE:-{secure_mode}}}"
AUTH_ENABLED="${{CONTAINER_REGISTRY_AUTH:-{auth_enabled}}}"
REGISTRY_USERNAME="${{CONTAINER_REGISTRY_USERNAME:-{registry_username}}}"
CA_CERT_DAYS="{ca_days}"
SERVER_CERT_DAYS="{cert_days}"
CUSTOM_SAN="{custom_san}"

# Directories for secure mode
PKI_DIR="$REGISTRY_STORAGE/pki"
AUTH_DIR="$REGISTRY_STORAGE/auth"

# Port-based PID/LOG files (allows multiple instances on different ports)
REGISTRY_PORT="${{REGISTRY_URL##*:}}"
PID_FILE="/tmp/container-registry-$REGISTRY_PORT.pid"
LOG_FILE="/tmp/container-registry-$REGISTRY_PORT.log"

# Generate tags based on strategy
# Usage: generate_tags "strategy1 strategy2 ..."
# Strategies: timestamp, sha/git, branch, semver, version, latest, arch
generate_tags() {{
    local strategy="${{1:-latest}}"
    local version="${{IMAGE_VERSION:-}}"
    local arch="${{TARGET_ARCH:-$DEFAULT_TARGET_ARCH}}"
    local tags=""

    for strat in $strategy; do
        case "$strat" in
            timestamp)
                tags="$tags $(date +%Y%m%d-%H%M%S)"
                ;;
            sha|git)
                local sha=$(git rev-parse --short HEAD 2>/dev/null || true)
                [ -n "$sha" ] && tags="$tags $sha"
                ;;
            branch)
                local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
                if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
                    # Sanitize: feature/login -> feature-login
                    tags="$tags $(echo $branch | tr '/_' '--')"
                fi
                ;;
            semver)
                if [ -n "$version" ]; then
                    local v="$version"
                    # Strip any suffix like +gitAUTOINC
                    v=$(echo "$v" | cut -d'+' -f1)
                    local major=$(echo "$v" | cut -d. -f1)
                    local minor=$(echo "$v" | cut -d. -f2)
                    local patch=$(echo "$v" | cut -d. -f3)
                    [ -n "$patch" ] && tags="$tags $major.$minor.$patch"
                    [ -n "$minor" ] && tags="$tags $major.$minor"
                    [ -n "$major" ] && [ "$major" != "$v" ] && tags="$tags $major"
                fi
                ;;
            version)
                if [ -n "$version" ]; then
                    local v=$(echo "$version" | cut -d'+' -f1)
                    tags="$tags $v"
                fi
                ;;
            latest)
                tags="$tags latest"
                ;;
            arch)
                if [ -n "$arch" ]; then
                    local arch_tags=""
                    for t in $tags; do
                        [ "$t" != "latest" ] && arch_tags="$arch_tags ${{t}}-${{arch}}"
                    done
                    tags="$tags $arch_tags"
                fi
                ;;
        esac
    done

    # Ensure at least one tag
    [ -z "$tags" ] && tags="latest"
    echo $tags
}}

# Parse a simple credentials file (key=value format)
# Sets CONTAINER_REGISTRY_USER, CONTAINER_REGISTRY_PASSWORD, CONTAINER_REGISTRY_TOKEN
parse_credsfile() {{
    local file="$1"
    [ ! -f "$file" ] && {{ echo "Error: Credentials file not found: $file" >&2; return 1; }}

    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Remove surrounding quotes
        value="${{value#\\"}}"
        value="${{value%\\"}}"
        value="${{value#'}}"
        value="${{value%'}}"

        case "$key" in
            CONTAINER_REGISTRY_USER) export CONTAINER_REGISTRY_USER="$value" ;;
            CONTAINER_REGISTRY_PASSWORD) export CONTAINER_REGISTRY_PASSWORD="$value" ;;
            CONTAINER_REGISTRY_TOKEN) export CONTAINER_REGISTRY_TOKEN="$value" ;;
        esac
    done < "$file"
}}

# ============================================================================
# Secure Registry PKI and Auth Setup
# ============================================================================

# Generate PKI infrastructure (CA + server certificate)
# Creates: $PKI_DIR/ca.key, ca.crt, server.key, server.crt
setup_pki() {{
    # Check for openssl
    if ! command -v openssl >/dev/null 2>&1; then
        echo "Error: openssl is required for secure mode but not found"
        echo "Install with: sudo apt install openssl"
        return 1
    fi

    mkdir -p "$PKI_DIR"

    # Generate CA if not exists
    if [ ! -f "$PKI_DIR/ca.key" ] || [ ! -f "$PKI_DIR/ca.crt" ]; then
        echo "Generating CA certificate..."
        openssl genrsa -out "$PKI_DIR/ca.key" 4096
        chmod 600 "$PKI_DIR/ca.key"

        openssl req -new -x509 -days "$CA_CERT_DAYS" \\
            -key "$PKI_DIR/ca.key" \\
            -out "$PKI_DIR/ca.crt" \\
            -subj "/CN=Yocto Container Registry CA/O=Yocto Project"

        echo "  Generated CA certificate: $PKI_DIR/ca.crt"
    else
        echo "  Using existing CA certificate: $PKI_DIR/ca.crt"
    fi

    # Generate server certificate if not exists
    if [ ! -f "$PKI_DIR/server.key" ] || [ ! -f "$PKI_DIR/server.crt" ]; then
        echo "Generating server certificate..."

        # Build SAN list
        # Extract host from registry URL (strip port)
        local registry_host=$(echo "$REGISTRY_URL" | cut -d':' -f1)
        local san_list="DNS:localhost,DNS:$registry_host,IP:127.0.0.1,IP:10.0.2.2"

        # Add custom SAN entries
        if [ -n "$CUSTOM_SAN" ]; then
            san_list="$san_list,$CUSTOM_SAN"
        fi

        echo "  SAN entries: $san_list"

        # Create OpenSSL config for SAN
        local ssl_conf="$PKI_DIR/openssl.cnf"
        cat > "$ssl_conf" << SSLEOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $registry_host
O = Yocto Project

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = $san_list
SSLEOF

        # Generate server key
        openssl genrsa -out "$PKI_DIR/server.key" 2048
        chmod 600 "$PKI_DIR/server.key"

        # Generate CSR
        openssl req -new \\
            -key "$PKI_DIR/server.key" \\
            -out "$PKI_DIR/server.csr" \\
            -config "$ssl_conf"

        # Sign with CA
        openssl x509 -req \\
            -in "$PKI_DIR/server.csr" \\
            -CA "$PKI_DIR/ca.crt" \\
            -CAkey "$PKI_DIR/ca.key" \\
            -CAcreateserial \\
            -out "$PKI_DIR/server.crt" \\
            -days "$SERVER_CERT_DAYS" \\
            -extensions v3_req \\
            -extfile "$ssl_conf"

        # Cleanup temp files
        rm -f "$PKI_DIR/server.csr" "$ssl_conf"

        echo "  Generated server certificate with SAN: localhost, $registry_host, 127.0.0.1, 10.0.2.2"
    else
        echo "  Using existing server certificate: $PKI_DIR/server.crt"
    fi
}}

# Setup htpasswd authentication
# Creates: $AUTH_DIR/htpasswd, $AUTH_DIR/password
setup_auth() {{
    # Check for htpasswd (from apache2-utils)
    if ! command -v htpasswd >/dev/null 2>&1; then
        echo "Error: htpasswd is required for secure mode but not found"
        echo "Install with: sudo apt install apache2-utils"
        return 1
    fi

    mkdir -p "$AUTH_DIR"

    local password=""

    # Password priority:
    # 1. CONTAINER_REGISTRY_PASSWORD environment variable
    # 2. Existing $AUTH_DIR/password file
    # 3. Auto-generate new password
    if [ -n "${{CONTAINER_REGISTRY_PASSWORD:-}}" ]; then
        password="$CONTAINER_REGISTRY_PASSWORD"
        echo "  Using password from environment variable"
    elif [ -f "$AUTH_DIR/password" ]; then
        password=$(cat "$AUTH_DIR/password")
        echo "  Using existing password from $AUTH_DIR/password"
    else
        # Generate random password (16 chars, alphanumeric)
        password=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
        echo "  Generated new random password"
    fi

    # Always update htpasswd (in case username changed)
    echo "  Creating htpasswd for user: $REGISTRY_USERNAME"
    htpasswd -Bbn "$REGISTRY_USERNAME" "$password" > "$AUTH_DIR/htpasswd"

    # Save password for reference (used by script and bbclass)
    echo -n "$password" > "$AUTH_DIR/password"
    chmod 600 "$AUTH_DIR/password"

    echo "  Password saved to: $AUTH_DIR/password"
}}

# Get TLS arguments for skopeo
# Usage: get_tls_args [dest|src]
# Returns: TLS arguments string for skopeo
get_tls_args() {{
    local direction="${{1:-dest}}"
    local prefix=""

    if [ "$direction" = "src" ]; then
        prefix="--src"
    else
        prefix="--dest"
    fi

    if [ "$SECURE_MODE" = "1" ] && [ -f "$PKI_DIR/ca.crt" ]; then
        # skopeo --dest-cert-dir expects a directory with only CA certs
        # If we point it at PKI_DIR which has ca.key, it thinks it's a client key
        # Create a clean certs directory with just the CA cert
        local certs_dir="$REGISTRY_STORAGE/certs"
        if [ ! -f "$certs_dir/ca.crt" ] || [ "$PKI_DIR/ca.crt" -nt "$certs_dir/ca.crt" ]; then
            mkdir -p "$certs_dir"
            cp "$PKI_DIR/ca.crt" "$certs_dir/ca.crt"
        fi
        echo "$prefix-cert-dir $certs_dir"
    else
        echo "$prefix-tls-verify=false"
    fi
}}

# Get the base URL (http or https depending on mode)
get_base_url() {{
    if [ "$SECURE_MODE" = "1" ]; then
        echo "https://$REGISTRY_URL"
    else
        echo "http://$REGISTRY_URL"
    fi
}}

# Get curl TLS arguments
get_curl_tls_args() {{
    if [ "$SECURE_MODE" = "1" ] && [ -f "$PKI_DIR/ca.crt" ]; then
        echo "--cacert $PKI_DIR/ca.crt"
    fi
}}

# Get curl auth arguments (for auth-enabled mode)
get_curl_auth_args() {{
    if [ "$AUTH_ENABLED" = "1" ] && [ -f "$AUTH_DIR/password" ]; then
        local password=$(cat "$AUTH_DIR/password")
        echo "-u $REGISTRY_USERNAME:$password"
    fi
}}

# Build authentication arguments for skopeo based on auth mode
# Usage: get_auth_args [dest|src]
# Returns: authentication arguments string for skopeo
get_auth_args() {{
    local direction="${{1:-dest}}"
    local mode="${{AUTH_MODE:-none}}"
    local prefix=""

    if [ "$direction" = "src" ]; then
        prefix="--src"
    else
        prefix="--dest"
    fi

    case "$mode" in
        none)
            # In auth-enabled mode with no explicit auth, auto-use generated credentials
            if [ "$AUTH_ENABLED" = "1" ] && [ -f "$AUTH_DIR/password" ]; then
                local password=$(cat "$AUTH_DIR/password")
                echo "$prefix-creds $REGISTRY_USERNAME:$password"
            else
                echo ""
            fi
            ;;
        home)
            # Use ~/.docker/config.json (like BB_USE_HOME_NPMRC pattern)
            local home_auth="$HOME/.docker/config.json"
            if [ ! -f "$home_auth" ]; then
                echo "Error: AUTH_MODE=home but $home_auth not found" >&2
                echo "Run 'docker login' first or use --authfile/--credsfile" >&2
                return 1
            fi
            echo "$prefix-authfile $home_auth"
            ;;
        authfile)
            [ -z "$AUTHFILE" ] && {{ echo "Error: --authfile required" >&2; return 1; }}
            [ ! -f "$AUTHFILE" ] && {{ echo "Error: Auth file not found: $AUTHFILE" >&2; return 1; }}
            echo "$prefix-authfile $AUTHFILE"
            ;;
        credsfile)
            [ -z "$CREDSFILE" ] && {{ echo "Error: --credsfile required" >&2; return 1; }}
            parse_credsfile "$CREDSFILE" || return 1
            # Fall through to check credentials
            if [ -n "${{CONTAINER_REGISTRY_TOKEN:-}}" ]; then
                echo "$prefix-registry-token $CONTAINER_REGISTRY_TOKEN"
            elif [ -n "${{CONTAINER_REGISTRY_USER:-}}" ] && [ -n "${{CONTAINER_REGISTRY_PASSWORD:-}}" ]; then
                echo "$prefix-creds $CONTAINER_REGISTRY_USER:$CONTAINER_REGISTRY_PASSWORD"
            else
                echo "Error: Credentials file must contain TOKEN or USER+PASSWORD" >&2
                return 1
            fi
            ;;
        env)
            # Environment variable mode (script only, not bbclass)
            if [ -n "${{CONTAINER_REGISTRY_TOKEN:-}}" ]; then
                echo "$prefix-registry-token $CONTAINER_REGISTRY_TOKEN"
            elif [ -n "${{CONTAINER_REGISTRY_USER:-}}" ] && [ -n "${{CONTAINER_REGISTRY_PASSWORD:-}}" ]; then
                echo "$prefix-creds $CONTAINER_REGISTRY_USER:$CONTAINER_REGISTRY_PASSWORD"
            else
                echo "Error: AUTH_MODE=env requires CONTAINER_REGISTRY_TOKEN or USER+PASSWORD" >&2
                return 1
            fi
            ;;
        creds)
            # Direct credentials (set by --creds option)
            [ -z "$DIRECT_CREDS" ] && {{ echo "Error: --creds value missing" >&2; return 1; }}
            echo "$prefix-creds $DIRECT_CREDS"
            ;;
        token)
            # Direct token (set by --token option)
            [ -z "$DIRECT_TOKEN" ] && {{ echo "Error: --token value missing" >&2; return 1; }}
            echo "$prefix-registry-token $DIRECT_TOKEN"
            ;;
        *)
            echo "Error: Unknown auth mode: $mode" >&2
            return 1
            ;;
    esac
}}

# Generate registry config file if it doesn't exist
# Called automatically on start when REGISTRY_STORAGE is overridden
generate_config() {{
    [ -f "$REGISTRY_CONFIG" ] && return 0

    echo "Generating registry config: $REGISTRY_CONFIG"
    local port="${{REGISTRY_URL##*:}}"
    mkdir -p "$(dirname "$REGISTRY_CONFIG")"

    {{
        echo "version: 0.1"
        echo "log:"
        echo "  level: info"
        echo "  formatter: text"
        echo "storage:"
        echo "  filesystem:"
        echo "    rootdirectory: $REGISTRY_STORAGE"
        echo "  delete:"
        echo "    enabled: true"
        echo "  redirect:"
        echo "    disable: true"
        echo "http:"
        echo "  addr: :$port"
        echo "  headers:"
        echo "    X-Content-Type-Options: [nosniff]"
        if [ "$SECURE_MODE" = "1" ]; then
            echo "  tls:"
            echo "    certificate: $PKI_DIR/server.crt"
            echo "    key: $PKI_DIR/server.key"
        fi
        if [ "$AUTH_ENABLED" = "1" ]; then
            echo "auth:"
            echo "  htpasswd:"
            echo "    realm: Yocto Container Registry"
            echo "    path: $AUTH_DIR/htpasswd"
        fi
        echo "health:"
        echo "  storagedriver:"
        echo "    enabled: true"
        echo "    interval: 10s"
        echo "    threshold: 3"
    }} > "$REGISTRY_CONFIG"
}}

cmd_start() {{
    # Migration: check old PID file location
    local old_pid_file="/tmp/container-registry.pid"
    if [ ! -f "$PID_FILE" ] && [ -f "$old_pid_file" ] && [ "$PID_FILE" != "$old_pid_file" ]; then
        if kill -0 "$(cat "$old_pid_file")" 2>/dev/null; then
            PID_FILE="$old_pid_file"
        else
            rm -f "$old_pid_file"
        fi
    fi

    if [ -f "$PID_FILE" ] && kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
        echo "Registry already running (PID: $(cat $PID_FILE))"
        return 0
    fi

    if [ ! -x "$REGISTRY_BIN" ]; then
        echo "Error: Registry binary not found at $REGISTRY_BIN"
        echo "Build it with: bitbake docker-distribution-native"
        return 1
    fi

    mkdir -p "$REGISTRY_STORAGE"

    # Generate config if it doesn't exist (e.g., when using custom REGISTRY_STORAGE)
    generate_config

    # Setup PKI for secure mode, auth is optional
    if [ "$SECURE_MODE" = "1" ]; then
        echo "Generating PKI infrastructure..."
        setup_pki || return 1
        echo ""
        if [ "$AUTH_ENABLED" = "1" ]; then
            echo "Setting up authentication..."
            setup_auth || return 1
            echo ""
            echo "Starting SECURE container registry (TLS + auth)..."
        else
            echo "Starting SECURE container registry (TLS only)..."
        fi
        echo "  URL:     https://$REGISTRY_URL"
    else
        echo "Starting container registry..."
        echo "  URL:     http://$REGISTRY_URL"
    fi

    echo "  Storage: $REGISTRY_STORAGE"
    echo "  Config:  $REGISTRY_CONFIG"
    if [ "$SECURE_MODE" = "1" ]; then
        echo "  PKI:     $PKI_DIR"
        if [ "$AUTH_ENABLED" = "1" ]; then
            echo "  Auth:    $AUTH_DIR"
            echo "  User:    $REGISTRY_USERNAME"
        fi
    fi

    nohup "$REGISTRY_BIN" serve "$REGISTRY_CONFIG" > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    sleep 2

    if kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
        echo "Registry started (PID: $(cat $PID_FILE))"
        echo "Logs: $LOG_FILE"
        if [ "$SECURE_MODE" = "1" ]; then
            echo ""
            echo "To install CA cert on targets, add to IMAGE_INSTALL:"
            echo '  IMAGE_INSTALL:append = " container-registry-ca"'
        fi
    else
        echo "Failed to start registry. Check $LOG_FILE"
        cat "$LOG_FILE"
        return 1
    fi
}}

cmd_stop() {{
    # Migration: check old PID file location
    local old_pid_file="/tmp/container-registry.pid"
    if [ ! -f "$PID_FILE" ] && [ -f "$old_pid_file" ] && [ "$PID_FILE" != "$old_pid_file" ]; then
        PID_FILE="$old_pid_file"
    fi

    if [ ! -f "$PID_FILE" ]; then
        echo "Registry not running"
        return 0
    fi

    local pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        echo "Stopping registry (PID: $pid)..."
        kill "$pid"
        rm -f "$PID_FILE"
        echo "Registry stopped"
    else
        rm -f "$PID_FILE"
        echo "Registry not running (stale PID file removed)"
    fi
}}

cmd_status() {{
    # Migration: check old PID file location
    local old_pid_file="/tmp/container-registry.pid"
    if [ ! -f "$PID_FILE" ] && [ -f "$old_pid_file" ] && [ "$PID_FILE" != "$old_pid_file" ]; then
        if kill -0 "$(cat "$old_pid_file")" 2>/dev/null; then
            PID_FILE="$old_pid_file"
        else
            rm -f "$old_pid_file"
        fi
    fi

    if [ -f "$PID_FILE" ] && kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
        echo "Registry running (PID: $(cat $PID_FILE))"
        local base_url=$(get_base_url)
        echo "URL: $base_url"
        local tls_args=$(get_curl_tls_args)
        local auth_args=$(get_curl_auth_args)
        if curl -s $tls_args $auth_args "$base_url/v2/" >/dev/null 2>&1; then
            echo "Status: healthy"
        else
            echo "Status: not responding"
        fi
        if [ "$SECURE_MODE" = "1" ]; then
            if [ "$AUTH_ENABLED" = "1" ]; then
                echo "Mode: secure (TLS + auth)"
            else
                echo "Mode: secure (TLS only)"
            fi
        fi
    else
        echo "Registry not running"
        return 1
    fi
}}

# ============================================================================
# Multi-Architecture Manifest List Support
# ============================================================================
# Always creates/updates manifest lists for tags, enabling multi-arch images.
# When pushing the same image name from different architectures, each push
# adds to the manifest list instead of overwriting.
# ============================================================================

# Get architecture from OCI image config
# Usage: get_oci_arch <oci_dir>
get_oci_arch() {{
    local oci_dir="$1"
    [ -f "$oci_dir/index.json" ] || return 1

    # Get manifest digest from index.json
    local manifest_digest=$(grep -o '"digest"[[:space:]]*:[[:space:]]*"sha256:[a-f0-9]*"' "$oci_dir/index.json" | head -1 | sed 's/.*sha256:\\([a-f0-9]*\\)".*/\\1/')
    [ -z "$manifest_digest" ] && return 1

    # Get config digest from manifest
    local manifest_file="$oci_dir/blobs/sha256/$manifest_digest"
    [ -f "$manifest_file" ] || return 1
    local config_digest=$(grep -o '"config"[^}}]*"digest"[[:space:]]*:[[:space:]]*"sha256:[a-f0-9]*"' "$manifest_file" | sed 's/.*sha256:\\([a-f0-9]*\\)".*/\\1/')
    [ -z "$config_digest" ] && return 1

    # Get architecture from config
    local config_file="$oci_dir/blobs/sha256/$config_digest"
    [ -f "$config_file" ] || return 1
    grep -o '"architecture"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | head -1 | sed 's/.*"\\([^"]*\\)"$/\\1/'
}}

# Check if a tag points to a manifest list (vs single manifest)
# Usage: is_manifest_list <image_ref>
# Returns: 0 if manifest list, 1 if single manifest or not found
is_manifest_list() {{
    local image="$1"
    local tag="$2"
    local base_url=$(get_base_url)
    local tls_args=$(get_curl_tls_args)
    local auth_args=$(get_curl_auth_args)

    local content_type=$(curl -s -I $tls_args $auth_args -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json" \\
        "$base_url/v2/$image/manifests/$tag" 2>/dev/null | grep -i "content-type" | head -1)

    echo "$content_type" | grep -qE "manifest.list|image.index"
}}

# Get existing manifest list for a tag (if any)
# Usage: get_manifest_list <image> <tag>
# Returns: JSON manifest list or empty string
get_manifest_list() {{
    local image="$1"
    local tag="$2"
    local base_url=$(get_base_url)
    local tls_args=$(get_curl_tls_args)
    local auth_args=$(get_curl_auth_args)

    curl -s $tls_args $auth_args -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json" \\
        "$base_url/v2/$image/manifests/$tag" 2>/dev/null
}}

# Get manifest digest and size for an image by tag
# Usage: get_manifest_info <image> <tag>
# Returns: digest:size or empty
get_manifest_info() {{
    local image="$1"
    local tag="$2"
    local base_url=$(get_base_url)
    local tls_args=$(get_curl_tls_args)
    local auth_args=$(get_curl_auth_args)

    local headers=$(curl -s -I $tls_args $auth_args -H "Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json" \\
        "$base_url/v2/$image/manifests/$tag" 2>/dev/null)

    local digest=$(echo "$headers" | grep -i "docker-content-digest" | awk '{{print $2}}' | tr -d '\\r\\n')
    local size=$(echo "$headers" | grep -i "content-length" | awk '{{print $2}}' | tr -d '\\r\\n')

    [ -n "$digest" ] && [ -n "$size" ] && echo "$digest:$size"
}}

# Push image by digest (returns the digest)
# Usage: push_by_digest <oci_dir> <image_name> [auth_args]
push_by_digest() {{
    local oci_dir="$1"
    local image_name="$2"
    local push_auth_args="${{3:-}}"
    local temp_tag="temp-${{RANDOM}}-$(date +%s)"

    # Get TLS arguments
    local tls_args=$(get_tls_args dest)

    # Push with temporary tag (capture output for error debugging)
    local push_output
    if ! push_output=$("$SKOPEO_BIN" copy $tls_args $push_auth_args \\
        "oci:$oci_dir" \\
        "docker://$REGISTRY_URL/$REGISTRY_NAMESPACE/$image_name:$temp_tag" 2>&1); then
        echo "ERROR: skopeo copy failed: $push_output" >&2
        return 1
    fi

    # Get digest for the pushed image
    local info=$(get_manifest_info "$REGISTRY_NAMESPACE/$image_name" "$temp_tag")
    local digest=$(echo "$info" | cut -d: -f1-2)  # sha256:xxx
    local size=$(echo "$info" | cut -d: -f3)

    # Validate we got both digest and size
    if [ -z "$digest" ] || [ -z "$size" ]; then
        echo "ERROR: Failed to get manifest info for pushed image (digest=$digest, size=$size)" >&2
        return 1
    fi

    # Delete the temp tag (leave the blobs)
    local base_url=$(get_base_url)
    local curl_tls_args=$(get_curl_tls_args)
    local curl_auth_args=$(get_curl_auth_args)
    curl -s -X DELETE $curl_tls_args $curl_auth_args "$base_url/v2/$REGISTRY_NAMESPACE/$image_name/manifests/$temp_tag" >/dev/null 2>&1 || true

    echo "$digest:$size"
}}

# Create or update manifest list for a tag
# Usage: update_manifest_list <image> <tag> <new_digest> <new_size> <new_arch>
update_manifest_list() {{
    local image="$1"
    local tag="$2"
    local new_digest="$3"
    local new_size="$4"
    local new_arch="$5"
    local new_os="${{6:-linux}}"

    # Normalize architecture for OCI
    case "$new_arch" in
        aarch64) new_arch="arm64" ;;
        x86_64)  new_arch="amd64" ;;
    esac

    local manifests=""

    # Check for existing manifest list or single manifest
    if is_manifest_list "$image" "$tag"; then
        # Get existing manifest list and extract manifests (excluding our arch)
        local existing=$(get_manifest_list "$image" "$tag")
        manifests=$(echo "$existing" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for m in data.get('manifests', []):
        p = m.get('platform', {{}})
        if p.get('architecture') != '$new_arch':
            print(json.dumps(m))
except: pass
" 2>/dev/null)
    else
        # Check if there's a single manifest at this tag
        local existing_info=$(get_manifest_info "$image" "$tag")
        if [ -n "$existing_info" ]; then
            # Get architecture of existing single manifest
            local existing_digest=$(echo "$existing_info" | cut -d: -f1-2)
            local existing_size=$(echo "$existing_info" | cut -d: -f3)

            # Inspect to get architecture
            local inspect_tls_args=$(get_tls_args dest | sed 's/--dest/--/')
            local existing_arch=$("$SKOPEO_BIN" inspect $inspect_tls_args \\
                "docker://$REGISTRY_URL/$image:$tag" 2>/dev/null | \\
                python3 -c "import sys,json; print(json.load(sys.stdin).get('Architecture',''))" 2>/dev/null)

            if [ -n "$existing_arch" ] && [ "$existing_arch" != "$new_arch" ] && [ -n "$existing_size" ]; then
                # Different arch - include it in manifest list (only if we have valid size)
                manifests=$(cat <<MANIFEST
{{"mediaType": "application/vnd.oci.image.manifest.v1+json", "digest": "$existing_digest", "size": $existing_size, "platform": {{"architecture": "$existing_arch", "os": "linux"}}}}
MANIFEST
)
            fi
        fi
    fi

    # Validate required parameters
    if [ -z "$new_digest" ] || [ -z "$new_size" ] || [ -z "$new_arch" ]; then
        echo "ERROR: Missing required manifest parameters (digest=$new_digest, size=$new_size, arch=$new_arch)" >&2
        return 1
    fi

    # Add our new manifest
    local new_manifest='{{"mediaType": "application/vnd.oci.image.manifest.v1+json", "digest": "'$new_digest'", "size": '$new_size', "platform": {{"architecture": "'$new_arch'", "os": "'$new_os'"}}}}'

    if [ -n "$manifests" ]; then
        manifests="$manifests
$new_manifest"
    else
        manifests="$new_manifest"
    fi

    # Create manifest list JSON
    local manifest_list
    manifest_list=$(python3 -c "
import sys, json
manifests = []
for i, line in enumerate(sys.stdin):
    line = line.strip()
    if line:
        try:
            manifests.append(json.loads(line))
        except json.JSONDecodeError as e:
            print(f'ERROR: Invalid JSON on line {{i+1}}: {{e}}', file=sys.stderr)
            print(f'  Content: {{line[:100]}}...', file=sys.stderr)
            sys.exit(1)
if not manifests:
    print('ERROR: No valid manifests to create list', file=sys.stderr)
    sys.exit(1)
result = {{
    'schemaVersion': 2,
    'mediaType': 'application/vnd.oci.image.index.v1+json',
    'manifests': manifests
}}
print(json.dumps(result, indent=2))
" <<< "$manifests")

    if [ -z "$manifest_list" ]; then
        echo "ERROR: Failed to create manifest list" >&2
        return 1
    fi

    # Push manifest list
    local base_url=$(get_base_url)
    local curl_tls_args=$(get_curl_tls_args)
    local curl_auth_args=$(get_curl_auth_args)
    local status=$(curl -s -o /dev/null -w "%{{http_code}}" -X PUT \\
        $curl_tls_args $curl_auth_args \\
        -H "Content-Type: application/vnd.oci.image.index.v1+json" \\
        -d "$manifest_list" \\
        "$base_url/v2/$image/manifests/$tag")

    [ "$status" = "201" ] || [ "$status" = "200" ]
}}

cmd_push() {{
    shift  # Remove 'push' from args

    # Parse options and positional args
    local explicit_tags=""
    local strategy="${{CONTAINER_REGISTRY_TAG_STRATEGY:-$DEFAULT_TAG_STRATEGY}}"
    local version="${{IMAGE_VERSION:-}}"
    local image_filter=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --tag|-t)
                explicit_tags="$explicit_tags $2"
                shift 2
                ;;
            --strategy|-s)
                strategy="$2"
                shift 2
                ;;
            --version|-v)
                version="$2"
                shift 2
                ;;
            # Authentication options
            --auth-mode)
                AUTH_MODE="$2"
                shift 2
                ;;
            --use-home-auth)
                AUTH_MODE="home"
                shift
                ;;
            --authfile)
                AUTH_MODE="authfile"
                AUTHFILE="$2"
                shift 2
                ;;
            --credsfile)
                AUTH_MODE="credsfile"
                CREDSFILE="$2"
                shift 2
                ;;
            --creds)
                AUTH_MODE="creds"
                DIRECT_CREDS="$2"
                shift 2
                ;;
            --token)
                AUTH_MODE="token"
                DIRECT_TOKEN="$2"
                shift 2
                ;;
            -*)
                echo "Unknown option: $1"
                return 1
                ;;
            *)
                # Positional arg = image name filter
                if [ -z "$image_filter" ]; then
                    image_filter="$1"
                fi
                shift
                ;;
        esac
    done

    # Explicit tags require an image name
    if [ -n "$explicit_tags" ] && [ -z "$image_filter" ]; then
        echo "Error: --tag requires an image name"
        echo "Usage: $0 push <image> --tag <tag>"
        echo ""
        echo "Examples:"
        echo "  $0 push container-base --tag v1.0.0"
        echo "  $0 push container-base --tag latest --tag v1.0.0"
        echo ""
        echo "To push all images, use a strategy instead:"
        echo "  $0 push --strategy 'timestamp latest'"
        return 1
    fi

    # Export version for generate_tags
    export IMAGE_VERSION="$version"

    local base_url=$(get_base_url)
    local curl_tls_args=$(get_curl_tls_args)
    local curl_auth_args=$(get_curl_auth_args)
    if ! curl -s $curl_tls_args $curl_auth_args "$base_url/v2/" >/dev/null 2>&1; then
        echo "Registry not responding at $base_url"
        echo "Start it first: $0 start"
        return 1
    fi

    # Get authentication arguments
    local auth_args
    auth_args=$(get_auth_args dest) || return 1

    # Determine tags to use
    local tags
    if [ -n "$explicit_tags" ]; then
        tags="$explicit_tags"
    else
        tags=$(generate_tags "$strategy")
    fi

    # Check if argument is a path to an OCI directory (contains / or ends with -oci)
    if [ -n "$image_filter" ] && [ -d "$image_filter" ] && [ -f "$image_filter/index.json" ]; then
        # Direct path mode: push single OCI directory
        local oci_dir="$image_filter"
        local name=$(basename "$oci_dir" | sed 's/-latest-oci$//' | sed 's/-oci$//')
        name=$(echo "$name" | sed 's/-qemux86-64//' | sed 's/-qemuarm64//')
        name=$(echo "$name" | sed 's/\\.rootfs-[0-9]*//')
        # Strip -multiarch suffix for cleaner registry names
        name=$(echo "$name" | sed 's/-multiarch$//')

        # Detect multi-arch OCI Image Index
        # Flat layout: index.json has multiple manifests with platform info
        # Nested layout: index.json → single image index blob → platform manifests
        local is_multiarch=0
        local platform_file="$oci_dir/index.json"
        local manifest_count=$(grep -c '"digest"' "$platform_file" 2>/dev/null || echo "0")
        local has_platform=$(grep -c '"platform"' "$platform_file" 2>/dev/null || echo "0")

        if [ "$manifest_count" -gt 1 ] && [ "$has_platform" -gt 0 ]; then
            is_multiarch=1
        elif grep -q 'image\\.index' "$platform_file" 2>/dev/null; then
            # Nested layout: follow digest to blob
            local idx_digest=$(grep -o '"sha256:[a-f0-9]*"' "$platform_file" 2>/dev/null | head -1 | tr -d '"' | sed 's/sha256://')
            if [ -n "$idx_digest" ] && [ -f "$oci_dir/blobs/sha256/$idx_digest" ]; then
                if grep -q '"platform"' "$oci_dir/blobs/sha256/$idx_digest" 2>/dev/null; then
                    platform_file="$oci_dir/blobs/sha256/$idx_digest"
                    is_multiarch=1
                fi
            fi
        fi

        if [ "$is_multiarch" = "1" ]; then
            # Multi-arch OCI Image Index: push with --all to preserve manifest list
            local platforms=$(grep -o '"architecture"[[:space:]]*:[[:space:]]*"[^"]*"' "$platform_file" | \\
                sed 's/.*"\\([^"]*\\)"$/\\1/' | tr '\\n' ' ')

            echo "Pushing multi-arch OCI Image Index: $oci_dir"
            echo "  Image name: $name"
            echo "  Platforms: $platforms"
            echo "  To registry: $REGISTRY_URL/$REGISTRY_NAMESPACE/"
            echo "  Tags: $tags"
            echo ""

            local tls_args=$(get_tls_args dest)
            for tag in $tags; do
                echo "  Pushing manifest list: $name:$tag"
                if "$SKOPEO_BIN" copy --all $tls_args $auth_args \\
                    "oci:$oci_dir" \\
                    "docker://$REGISTRY_URL/$REGISTRY_NAMESPACE/$name:$tag" 2>&1; then
                    echo "  -> $REGISTRY_URL/$REGISTRY_NAMESPACE/$name:$tag (manifest list: $platforms)"
                else
                    echo "  ERROR: Failed to push multi-arch image"
                    return 1
                fi
            done

            echo ""
            echo "Done."
            return 0
        fi

        # Single-arch OCI: push normally
        local arch=$(get_oci_arch "$oci_dir")
        [ -z "$arch" ] && arch="unknown"

        echo "Pushing OCI directory: $oci_dir"
        echo "  Image name: $name ($arch)"
        echo "  To registry: $REGISTRY_URL/$REGISTRY_NAMESPACE/"
        echo "  Tags: $tags"
        echo ""

        echo "  Uploading image blobs..."
        local digest_info
        if ! digest_info=$(push_by_digest "$oci_dir" "$name" "$auth_args"); then
            echo "  ERROR: Failed to push image"
            return 1
        fi
        local digest=$(echo "$digest_info" | cut -d: -f1-2)
        local size=$(echo "$digest_info" | cut -d: -f3)

        if [ -z "$digest" ] || [ -z "$size" ]; then
            echo "  ERROR: Failed to get image digest/size (digest=$digest, size=$size)"
            return 1
        fi

        echo "  Image digest: $digest"

        for tag in $tags; do
            echo "  Creating/updating manifest list: $tag"
            if update_manifest_list "$REGISTRY_NAMESPACE/$name" "$tag" "$digest" "$size" "$arch"; then
                echo "  -> $REGISTRY_URL/$REGISTRY_NAMESPACE/$name:$tag (manifest list)"
            else
                echo "  WARNING: Failed to update manifest list, falling back to direct push"
                "$SKOPEO_BIN" copy --dest-tls-verify=false $auth_args \\
                    "oci:$oci_dir" \\
                    "docker://$REGISTRY_URL/$REGISTRY_NAMESPACE/$name:$tag"
            fi
        done

        echo ""
        echo "Done."
        return 0
    fi

    # Name filter mode or push all: scan machine directories
    if [ -n "$image_filter" ]; then
        echo "Pushing image: $image_filter (all architectures)"
    else
        echo "Pushing all OCI images"
    fi
    echo "Scanning: $DEPLOY_DIR_IMAGES/*/"
    echo "To registry: $REGISTRY_URL/$REGISTRY_NAMESPACE/"
    echo "Tags: $tags"
    echo "(Multi-arch manifest lists enabled)"
    echo ""

    local found=0

    # Iterate over all machine directories (e.g., qemuarm64, qemux86-64)
    for machine_dir in "$DEPLOY_DIR_IMAGES"/*/; do
        [ -d "$machine_dir" ] || continue

        local machine_name=$(basename "$machine_dir")

        # Find OCI directories in this machine's deploy dir
        for oci_dir in "$machine_dir"*-oci; do
            [ -d "$oci_dir" ] || continue
            [ -f "$oci_dir/index.json" ] || continue

            name=$(basename "$oci_dir" | sed 's/-latest-oci$//' | sed 's/-oci$//')
            # Remove machine suffix
            name=$(echo "$name" | sed 's/-qemux86-64//' | sed 's/-qemuarm64//')
            # Remove rootfs timestamp
            name=$(echo "$name" | sed 's/\\.rootfs-[0-9]*//')

            # Filter by image name if specified
            if [ -n "$image_filter" ]; then
                # Match exact name or name.rootfs variant
                case "$name" in
                    "$image_filter"|"$image_filter.rootfs")
                        : # match
                        ;;
                    *)
                        continue
                        ;;
                esac
            fi

            found=1

            # Get architecture from OCI image
            local arch=$(get_oci_arch "$oci_dir")
            [ -z "$arch" ] && arch="unknown"
            echo "Pushing: $name ($arch) [from $machine_name]"

            # Push image by digest first
            echo "  Uploading image blobs..."
            local digest_info
            if ! digest_info=$(push_by_digest "$oci_dir" "$name" "$auth_args"); then
                echo "  ERROR: Failed to push image"
                continue
            fi
            local digest=$(echo "$digest_info" | cut -d: -f1-2)
            local size=$(echo "$digest_info" | cut -d: -f3)

            if [ -z "$digest" ] || [ -z "$size" ]; then
                echo "  ERROR: Failed to get image digest/size (digest=$digest, size=$size)"
                continue
            fi

            echo "  Image digest: $digest"

            # Update manifest list for each tag
            for tag in $tags; do
                echo "  Creating/updating manifest list: $tag"
                if update_manifest_list "$REGISTRY_NAMESPACE/$name" "$tag" "$digest" "$size" "$arch"; then
                    echo "  -> $REGISTRY_URL/$REGISTRY_NAMESPACE/$name:$tag (manifest list)"
                else
                    echo "  WARNING: Failed to update manifest list, falling back to direct push"
                    "$SKOPEO_BIN" copy --dest-tls-verify=false $auth_args \\
                        "oci:$oci_dir" \\
                        "docker://$REGISTRY_URL/$REGISTRY_NAMESPACE/$name:$tag"
                fi
            done
            echo ""
        done
    done

    if [ -n "$image_filter" ] && [ "$found" = "0" ]; then
        echo "Error: Image '$image_filter' not found in $DEPLOY_DIR_IMAGES"
        echo ""
        echo "Available images:"
        for machine_dir in "$DEPLOY_DIR_IMAGES"/*/; do
            [ -d "$machine_dir" ] || continue
            for oci_dir in "$machine_dir"*-oci; do
                [ -d "$oci_dir" ] || continue
                [ -f "$oci_dir/index.json" ] || continue
                local arch=$(get_oci_arch "$oci_dir")
                n=$(basename "$oci_dir" | sed 's/-latest-oci$//' | sed 's/-oci$//' | sed 's/-qemux86-64//' | sed 's/-qemuarm64//' | sed 's/\\.rootfs-[0-9]*//')
                echo "  $n ($arch)"
            done
        done | sort -u
        return 1
    fi

    echo ""
    echo "Done. Catalog:"
    cmd_catalog
}}

cmd_catalog() {{
    local base_url=$(get_base_url)
    local tls_args=$(get_curl_tls_args)
    local auth_args=$(get_curl_auth_args)
    curl -s $tls_args $auth_args "$base_url/v2/_catalog" | python3 -m json.tool 2>/dev/null || \\
        curl -s $tls_args $auth_args "$base_url/v2/_catalog"
}}

cmd_tags() {{
    local image="${{2:-}}"

    if [ -z "$image" ]; then
        echo "Usage: $0 tags <image>"
        echo ""
        echo "Examples:"
        echo "  $0 tags alpine"
        echo "  $0 tags yocto/container-base"
        return 1
    fi

    # Add namespace if not already qualified
    if ! echo "$image" | grep -q '/'; then
        image="$REGISTRY_NAMESPACE/$image"
    fi

    local base_url=$(get_base_url)
    local tls_args=$(get_curl_tls_args)
    local auth_args=$(get_curl_auth_args)
    local result=$(curl -s $tls_args $auth_args "$base_url/v2/$image/tags/list")

    # Check for errors or empty result
    if [ -z "$result" ]; then
        echo "Image not found: $image"
        return 1
    fi

    if echo "$result" | grep -qE '"errors"|NAME_UNKNOWN|MANIFEST_UNKNOWN'; then
        echo "Image not found: $image"
        return 1
    fi

    # Check if tags array is null or empty
    if echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('tags') else 1)" 2>/dev/null; then
        echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
    else
        echo "Image not found: $image"
        return 1
    fi
}}

cmd_list() {{
    local base_url=$(get_base_url)
    local tls_args=$(get_curl_tls_args)
    local auth_args=$(get_curl_auth_args)

    if ! curl -s $tls_args $auth_args "$base_url/v2/" >/dev/null 2>&1; then
        echo "Registry not responding at $base_url"
        return 1
    fi

    echo "Images in $REGISTRY_URL:"
    echo ""

    local repos=$(curl -s $tls_args $auth_args "$base_url/v2/_catalog" | python3 -c "import sys,json; print('\\n'.join(json.load(sys.stdin).get('repositories',[])))" 2>/dev/null)

    if [ -z "$repos" ]; then
        echo "  (none)"
        return 0
    fi

    for repo in $repos; do
        local tags=$(curl -s $tls_args $auth_args "$base_url/v2/$repo/tags/list" | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin).get('tags',[])))" 2>/dev/null)
        if [ -n "$tags" ]; then
            echo "  $repo: $tags"
        else
            echo "  $repo: (no tags)"
        fi
    done
}}

cmd_import() {{
    shift  # Remove 'import' from args

    local source=""
    local dest_name=""
    local src_auth_args=""

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            # Source registry authentication options
            --src-authfile)
                src_auth_args="--src-authfile $2"
                shift 2
                ;;
            --src-credsfile)
                parse_credsfile "$2" || return 1
                if [ -n "${{CONTAINER_REGISTRY_TOKEN:-}}" ]; then
                    src_auth_args="--src-registry-token $CONTAINER_REGISTRY_TOKEN"
                elif [ -n "${{CONTAINER_REGISTRY_USER:-}}" ] && [ -n "${{CONTAINER_REGISTRY_PASSWORD:-}}" ]; then
                    src_auth_args="--src-creds $CONTAINER_REGISTRY_USER:$CONTAINER_REGISTRY_PASSWORD"
                else
                    echo "Error: Credentials file must contain TOKEN or USER+PASSWORD" >&2
                    return 1
                fi
                shift 2
                ;;
            --src-creds)
                src_auth_args="--src-creds $2"
                shift 2
                ;;
            --src-token)
                src_auth_args="--src-registry-token $2"
                shift 2
                ;;
            -*)
                echo "Unknown option: $1"
                return 1
                ;;
            *)
                # Positional args: source, then dest_name
                if [ -z "$source" ]; then
                    source="$1"
                elif [ -z "$dest_name" ]; then
                    dest_name="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$source" ]; then
        echo "Usage: $0 import <source-image> [local-name] [options]"
        echo ""
        echo "Examples:"
        echo "  $0 import docker.io/library/alpine:latest"
        echo "  $0 import docker.io/library/alpine:latest my-alpine"
        echo "  $0 import quay.io/podman/hello:latest hello"
        echo "  $0 import ghcr.io/owner/image:tag"
        echo ""
        echo "Authentication options (for source registry):"
        echo "  --src-authfile <path>    Docker config.json for source"
        echo "  --src-credsfile <path>   Credentials file for source"
        echo "  --src-creds <user:pass>  Direct credentials for source"
        echo "  --src-token <token>      Bearer token for source"
        return 1
    fi

    local base_url=$(get_base_url)
    local curl_tls_args=$(get_curl_tls_args)
    local curl_auth_args=$(get_curl_auth_args)
    if ! curl -s $curl_tls_args $curl_auth_args "$base_url/v2/" >/dev/null 2>&1; then
        echo "Registry not responding at $base_url"
        echo "Start it first: $0 start"
        return 1
    fi

    # Extract image name if not provided
    if [ -z "$dest_name" ]; then
        # docker.io/library/alpine:latest -> alpine
        # quay.io/podman/hello:latest -> hello
        dest_name=$(echo "$source" | rev | cut -d'/' -f1 | rev | cut -d':' -f1)
    fi

    # Extract tag from source, default to latest
    local tag="latest"
    if echo "$source" | grep -q ':'; then
        tag=$(echo "$source" | rev | cut -d':' -f1 | rev)
    fi

    echo "Importing: $source"
    echo "       To: $REGISTRY_URL/$REGISTRY_NAMESPACE/$dest_name:$tag"
    echo ""

    # Get destination TLS and auth arguments
    local dest_tls_args=$(get_tls_args dest)
    local dest_auth_args=$(get_auth_args dest) || return 1

    "$SKOPEO_BIN" copy \\
        $dest_tls_args \\
        $dest_auth_args \\
        $src_auth_args \\
        "docker://$source" \\
        "docker://$REGISTRY_URL/$REGISTRY_NAMESPACE/$dest_name:$tag"

    echo ""
    echo "Import complete. Pull with:"
    echo "  vdkr --registry $REGISTRY_URL/$REGISTRY_NAMESPACE pull $dest_name"
    echo "  # or configure: vdkr vconfig registry $REGISTRY_URL/$REGISTRY_NAMESPACE"
    echo "  # then: vdkr pull $dest_name"
}}

cmd_delete() {{
    local image="${{2:-}}"

    if [ -z "$image" ]; then
        echo "Usage: $0 delete <image>[:<tag>]"
        echo ""
        echo "Examples:"
        echo "  $0 delete container-base:v1.0.0     # Delete specific tag"
        echo "  $0 delete container-base:20260112-143022"
        echo "  $0 delete yocto/alpine:latest       # With namespace"
        echo ""
        echo "Note: Deleting a tag removes the manifest reference."
        echo "Run garbage collection to reclaim disk space."
        return 1
    fi

    local base_url=$(get_base_url)
    local tls_args=$(get_curl_tls_args)
    local auth_args=$(get_curl_auth_args)

    if ! curl -s $tls_args $auth_args "$base_url/v2/" >/dev/null 2>&1; then
        echo "Registry not responding at $base_url"
        return 1
    fi

    # Parse image:tag
    local name tag
    if echo "$image" | grep -q ':'; then
        name=$(echo "$image" | rev | cut -d':' -f2- | rev)
        tag=$(echo "$image" | rev | cut -d':' -f1 | rev)
    else
        echo "Error: Tag required. Use format: <image>:<tag>"
        echo "Example: $0 delete container-base:v1.0.0"
        return 1
    fi

    # Add namespace if not already qualified
    if ! echo "$name" | grep -q '/'; then
        name="$REGISTRY_NAMESPACE/$name"
    fi

    echo "Deleting: $name:$tag"

    # Get the digest for the tag (try OCI format first, then Docker V2)
    local digest=""
    for accept in "application/vnd.oci.image.manifest.v1+json" \
                  "application/vnd.docker.distribution.manifest.v2+json"; do
        digest=$(curl -s -I $tls_args $auth_args -H "Accept: $accept" \
            "$base_url/v2/$name/manifests/$tag" 2>/dev/null \
            | grep -i "docker-content-digest" | awk '{{print $2}}' | tr -d '\r\n')
        [ -n "$digest" ] && break
    done

    if [ -z "$digest" ]; then
        echo "Error: Tag not found: $name:$tag"
        return 1
    fi

    echo "  Digest: $digest"

    # Delete by digest
    local status=$(curl -s -o /dev/null -w "%{{http_code}}" -X DELETE \
        $tls_args $auth_args \
        "$base_url/v2/$name/manifests/$digest")

    if [ "$status" = "202" ]; then
        echo "  Deleted successfully"
        echo ""
        echo "Note: Run garbage collection to reclaim disk space:"
        echo "  $0 gc"
    elif [ "$status" = "405" ]; then
        echo "Error: Deletion not enabled in registry config"
        echo "Add 'storage.delete.enabled: true' to registry config and restart"
        return 1
    else
        echo "Error: Delete failed (HTTP $status)"
        return 1
    fi
}}

cmd_gc() {{
    echo "Running garbage collection..."
    echo ""

    if [ ! -x "$REGISTRY_BIN" ]; then
        echo "Error: Registry binary not found at $REGISTRY_BIN"
        echo "Build it with: bitbake docker-distribution-native"
        return 1
    fi

    # Check if registry is running
    local was_running=0
    if [ -f "$PID_FILE" ] && kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
        was_running=1
        echo "Stopping registry for garbage collection..."
        cmd_stop
        sleep 1
    fi

    echo "Collecting garbage from: $REGISTRY_STORAGE"
    echo ""

    # Run garbage collection (dry-run first to show what would be deleted)
    "$REGISTRY_BIN" garbage-collect --dry-run "$REGISTRY_CONFIG" 2>&1 || true
    echo ""

    read -p "Proceed with garbage collection? [y/N] " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        "$REGISTRY_BIN" garbage-collect "$REGISTRY_CONFIG"
        echo ""
        echo "Garbage collection complete."
    else
        echo "Cancelled."
    fi

    # Restart if it was running
    if [ "$was_running" = "1" ]; then
        echo ""
        echo "Restarting registry..."
        cmd_start
    fi
}}

cmd_help() {{
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  start                  Start the container registry server"
    echo "  stop                   Stop the container registry server"
    echo "  status                 Check if registry is running"
    echo "  push [image] [opts]    Push OCI images to registry"
    echo "  import <image> [name]  Import 3rd party image to registry"
    echo "  delete <image>:<tag>   Delete a tagged image from registry"
    echo "  gc                     Garbage collect unreferenced blobs"
    echo "  list                   List all images with tags"
    echo "  tags <image>           List tags for an image"
    echo "  catalog                List image names (raw API)"
    echo "  help                   Show this help"
    echo ""
    echo "Push options:"
    echo "  <image>                Image name (required when using --tag)"
    echo "  --tag, -t <tag>        Explicit tag (can be repeated, requires image name)"
    echo "  --strategy, -s <str>   Tag strategy (default: $DEFAULT_TAG_STRATEGY)"
    echo "  --version, -v <ver>    Version for semver strategy (e.g., 1.2.3)"
    echo ""
    echo "Authentication options (for push command):"
    echo "  --use-home-auth        Use ~/.docker/config.json (like BB_USE_HOME_NPMRC)"
    echo "  --authfile <path>      Docker-style config.json file"
    echo "  --credsfile <path>     Simple key=value credentials file"
    echo "  --creds <user:pass>    Direct credentials (less secure)"
    echo "  --token <token>        Bearer token directly (less secure)"
    echo "  --auth-mode <mode>     Mode: none, home, authfile, credsfile, env"
    echo ""
    echo "Import authentication options (for source registry):"
    echo "  --src-authfile <path>  Docker config.json for source"
    echo "  --src-credsfile <path> Credentials file for source"
    echo "  --src-creds <user:pass> Direct credentials for source"
    echo "  --src-token <token>    Bearer token for source"
    echo ""
    echo "Tag strategies (can combine: 'sha branch latest'):"
    echo "  timestamp              YYYYMMDD-HHMMSS format"
    echo "  sha, git               Short git commit hash"
    echo "  branch                 Git branch name (sanitized)"
    echo "  semver                 Nested SemVer (1.2.3 -> 1.2.3, 1.2, 1)"
    echo "  version                Single version tag from --version"
    echo "  latest                 The 'latest' tag"
    echo "  arch                   Append architecture suffix to other tags"
    echo ""
    echo "Multi-architecture support:"
    echo "  Push scans all machine directories under DEPLOY_DIR_IMAGES and creates"
    echo "  manifest lists containing all architectures found for each container."
    echo ""
    echo "  Workflow:"
    echo "    MACHINE=qemuarm64 bitbake myapp"
    echo "    MACHINE=qemux86-64 bitbake myapp"
    echo "    $0 push                   # Scans all machines, creates manifest lists"
    echo ""
    echo "  Result: myapp:latest is a manifest list with both arm64 and amd64"
    echo ""
    echo "Examples:"
    echo "  $0 start"
    echo "  $0 push                                    # Push all from all machines"
    echo "  $0 push container-base                     # Push by name (all archs found)"
    echo "  $0 push /path/to/container-base-latest-oci # Push by path (single OCI dir)"
    echo "  $0 push container-base --tag v1.0.0        # Explicit tag"
    echo "  $0 push container-base -t latest -t v1.0.0 # Multiple explicit tags"
    echo "  $0 push --strategy 'sha branch latest'     # All images, strategy"
    echo "  $0 push --strategy semver --version 1.2.3  # All images, SemVer"
    echo ""
    echo "Authentication examples:"
    echo "  $0 push --use-home-auth                    # Use ~/.docker/config.json"
    echo "  $0 push --authfile /path/to/auth.json      # Explicit auth file"
    echo "  $0 push --credsfile ~/.config/creds        # Simple credentials file"
    echo "  $0 import ghcr.io/org/img:v1 --src-credsfile ~/.config/ghcr-creds"
    echo ""
    echo "Import examples:"
    echo "  $0 import docker.io/library/alpine:latest"
    echo "  $0 import docker.io/library/busybox:latest my-busybox"
    echo "  $0 import ghcr.io/org/private:v1 --src-authfile ~/.docker/config.json"
    echo ""
    echo "Other examples:"
    echo "  $0 delete container-base:20260112-143022"
    echo "  $0 list"
    echo "  $0 tags container-base"
    echo ""
    echo "Environment variables:"
    echo "  DEPLOY_DIR_IMAGES                 Override parent of deploy dirs (scans */)"
    echo "  DEPLOY_DIR_IMAGE                  Override single machine deploy dir"
    echo "  CONTAINER_REGISTRY_TAG_STRATEGY   Override default tag strategy"
    echo "  IMAGE_VERSION                     Version for semver/version strategies"
    echo "  TARGET_ARCH                       Architecture for arch strategy"
    echo ""
    echo "Authentication environment variables:"
    echo "  CONTAINER_REGISTRY_AUTH_MODE      Auth mode: none, home, authfile, credsfile, env"
    echo "  CONTAINER_REGISTRY_AUTHFILE       Path to Docker config.json"
    echo "  CONTAINER_REGISTRY_CREDSFILE      Path to simple credentials file"
    echo "  CONTAINER_REGISTRY_USER           Username (env mode only)"
    echo "  CONTAINER_REGISTRY_PASSWORD       Password (env mode only)"
    echo "  CONTAINER_REGISTRY_TOKEN          Token (env mode only)"
    echo ""
    echo "Configuration (baked from bitbake):"
    echo "  Registry URL:   $REGISTRY_URL"
    echo "  Namespace:      $REGISTRY_NAMESPACE"
    echo "  Tag strategy:   $DEFAULT_TAG_STRATEGY"
    echo "  Target arch:    $DEFAULT_TARGET_ARCH"
    echo "  Storage:        $REGISTRY_STORAGE"
    echo "  Deploy dirs:    $DEPLOY_DIR_IMAGES/*/"
    if [ "$SECURE_MODE" = "1" ]; then
        echo ""
        if [ "$AUTH_ENABLED" = "1" ]; then
            echo "Secure mode: ENABLED (TLS + authentication)"
        else
            echo "Secure mode: ENABLED (TLS only)"
        fi
        echo "  PKI directory:  $PKI_DIR"
        echo ""
        echo "  CA certificate: $PKI_DIR/ca.crt"
        echo '    Install on targets: IMAGE_INSTALL:append = " container-registry-ca"'
        if [ "$AUTH_ENABLED" = "1" ]; then
            echo ""
            echo "Authentication: ENABLED"
            echo "  Auth directory: $AUTH_DIR"
            echo "  Username:       $REGISTRY_USERNAME"
            echo "  Password file:  $AUTH_DIR/password"
            echo "    View password: cat $AUTH_DIR/password"
        fi
    fi
}}

case "${{1:-help}}" in
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    status)  cmd_status ;;
    push)    cmd_push "$@" ;;
    import)  cmd_import "$@" ;;
    delete)  cmd_delete "$@" ;;
    gc)      cmd_gc ;;
    list)    cmd_list ;;
    tags)    cmd_tags "$@" ;;
    catalog) cmd_catalog ;;
    help|--help|-h) cmd_help ;;
    *) echo "Unknown command: $1"; cmd_help; exit 1 ;;
esac
'''

    with open(script_path, 'w') as f:
        f.write(script)

    # Make executable
    os.chmod(script_path, os.stat(script_path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    bb.plain("")
    bb.plain("=" * 70)
    bb.plain("Generated container registry helper script:")
    bb.plain(f"  {script_path}")
    bb.plain("")
    bb.plain("Usage:")
    bb.plain(f"  {script_path} start    # Start registry server")
    bb.plain(f"  {script_path} push     # Push OCI images to registry")
    bb.plain(f"  {script_path} catalog  # List images in registry")
    bb.plain(f"  {script_path} stop     # Stop registry server")
    bb.plain("=" * 70)
    bb.plain("")
}

do_generate_registry_script[depends] += "docker-distribution-native:do_populate_sysroot skopeo-native:do_populate_sysroot openssl-native:do_populate_sysroot"
addtask do_generate_registry_script

EXCLUDE_FROM_WORLD = "1"
