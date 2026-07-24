# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# container-registry.bbclass
# ===========================================================================
# Container registry operations for pushing OCI images to registries
# ===========================================================================
#
# This class provides functions to push OCI images from the deploy directory
# to a container registry. It works with docker-distribution, Docker Hub,
# or any OCI-compliant registry.
#
# Usage:
#   inherit container-registry
#
#   # In do_populate_registry task:
#   container_registry_push(d, oci_path, image_name)
#
# Configuration:
#   CONTAINER_REGISTRY_URL = "localhost:5000"      # Registry endpoint
#   CONTAINER_REGISTRY_NAMESPACE = "yocto"         # Image namespace
#   CONTAINER_REGISTRY_TLS_VERIFY = "false"        # TLS verification
#   CONTAINER_REGISTRY_TAG_STRATEGY = "timestamp latest"  # Tag generation
#   CONTAINER_REGISTRY_STORAGE = "${TOPDIR}/container-registry"  # Persistent storage
#   CONTAINER_REGISTRY_SECURE = "1"                # Enable TLS (HTTPS)
#   CONTAINER_REGISTRY_AUTH = "1"                  # Enable htpasswd auth (requires SECURE=1)
#
# ===========================================================================

# Registry configuration
CONTAINER_REGISTRY_URL ?= "localhost:5000"
CONTAINER_REGISTRY_NAMESPACE ?= "yocto"
CONTAINER_REGISTRY_TLS_VERIFY ?= "false"
CONTAINER_REGISTRY_TAG_STRATEGY ?= "timestamp latest"

# Storage location for registry data (default: outside tmp/, persists across builds)
# Set in local.conf to customize, e.g.:
#   CONTAINER_REGISTRY_STORAGE = "/data/container-registry"
#   CONTAINER_REGISTRY_STORAGE = "${TOPDIR}/../container-registry"
CONTAINER_REGISTRY_STORAGE ?= "${TOPDIR}/container-registry"

# Authentication configuration
# Modes: "none" (default), "home", "authfile", "credsfile"
#   none     - No authentication (local/anonymous registries)
#   home     - Use ~/.docker/config.json (opt-in, like BB_USE_HOME_NPMRC)
#   authfile - Explicit path to Docker-style config.json
#   credsfile - Simple key=value credentials file
CONTAINER_REGISTRY_AUTH_MODE ?= "none"

# Path to Docker-style auth file (config.json format)
# Used when AUTH_MODE = "authfile"
CONTAINER_REGISTRY_AUTHFILE ?= ""

# Path to simple credentials file (key=value format)
# Used when AUTH_MODE = "credsfile"
# File contains: CONTAINER_REGISTRY_USER + CONTAINER_REGISTRY_PASSWORD, or CONTAINER_REGISTRY_TOKEN
CONTAINER_REGISTRY_CREDSFILE ?= ""

# Insecure registry mode (HTTP, no TLS) - legacy compatibility
CONTAINER_REGISTRY_INSECURE ?= "0"

# Secure registry mode (opt-in)
# When enabled, generates TLS certificates for HTTPS
CONTAINER_REGISTRY_SECURE ?= "0"

# Authentication mode (opt-in, requires SECURE=1)
# When enabled, generates htpasswd credentials
CONTAINER_REGISTRY_AUTH ?= "0"

# Credentials for auth mode (password empty = auto-generate)
CONTAINER_REGISTRY_USERNAME ?= "yocto"
CONTAINER_REGISTRY_PASSWORD ?= ""

# Certificate validity periods
CONTAINER_REGISTRY_CERT_DAYS ?= "365"
CONTAINER_REGISTRY_CA_DAYS ?= "3650"

# Custom SAN entries (auto-includes localhost, 127.0.0.1, 10.0.2.2, registry host)
CONTAINER_REGISTRY_CERT_SAN ?= ""

# Path to CA certificate (auto-set in secure mode)
CONTAINER_REGISTRY_CA_CERT ?= "${CONTAINER_REGISTRY_STORAGE}/pki/ca.crt"

# Require skopeo-native for registry operations
DEPENDS += "skopeo-native"

# Validate conflicting settings at parse time
python __anonymous() {
    secure = d.getVar('CONTAINER_REGISTRY_SECURE') == '1'
    insecure = d.getVar('CONTAINER_REGISTRY_INSECURE') == '1'
    auth = d.getVar('CONTAINER_REGISTRY_AUTH') == '1'

    if secure and insecure:
        bb.fatal("CONTAINER_REGISTRY_SECURE and CONTAINER_REGISTRY_INSECURE cannot both be set to '1'. "
                 "Use CONTAINER_REGISTRY_SECURE='1' for TLS, or CONTAINER_REGISTRY_INSECURE='1' for HTTP.")

    if auth and not secure:
        bb.warn("CONTAINER_REGISTRY_AUTH='1' requires CONTAINER_REGISTRY_SECURE='1'. "
                "Authentication without TLS is insecure. Enabling SECURE mode automatically.")
        d.setVar('CONTAINER_REGISTRY_SECURE', '1')
}

def _container_registry_parse_credsfile(filepath):
    """Parse a simple key=value credentials file.

    Returns dict with CONTAINER_REGISTRY_USER, CONTAINER_REGISTRY_PASSWORD,
    and/or CONTAINER_REGISTRY_TOKEN.
    """
    creds = {}
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '=' in line:
                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip()
                # Remove quotes if present
                if value.startswith('"') and value.endswith('"'):
                    value = value[1:-1]
                elif value.startswith("'") and value.endswith("'"):
                    value = value[1:-1]
                creds[key] = value
    return creds

def _container_registry_get_auth_args(d):
    """Build skopeo authentication arguments based on auth mode."""
    import os

    auth_mode = d.getVar('CONTAINER_REGISTRY_AUTH_MODE') or 'none'
    secure_mode = d.getVar('CONTAINER_REGISTRY_SECURE') == '1'

    if auth_mode == 'none':
        # In secure mode with no explicit auth, auto-use generated credentials
        if secure_mode:
            storage = d.getVar('CONTAINER_REGISTRY_STORAGE')
            password_file = os.path.join(storage, 'auth', 'password')
            if os.path.exists(password_file):
                with open(password_file, 'r') as f:
                    password = f.read().strip()
                username = d.getVar('CONTAINER_REGISTRY_USERNAME') or 'yocto'
                bb.note(f"Using auto-generated credentials for secure registry (user: {username})")
                return ['--dest-creds', f'{username}:{password}']
        return []

    if auth_mode == 'home':
        # Use ~/.docker/config.json (opt-in, like BB_USE_HOME_NPMRC)
        home = os.environ.get('HOME', '')
        authfile = os.path.join(home, '.docker', 'config.json')
        if not os.path.exists(authfile):
            bb.fatal(f"CONTAINER_REGISTRY_AUTH_MODE='home' but {authfile} not found. "
                     f"Run 'docker login' or use 'authfile'/'credsfile' mode instead.")
        bb.note(f"Using home Docker config for registry auth: {authfile}")
        return ['--dest-authfile', authfile]

    if auth_mode == 'authfile':
        authfile = d.getVar('CONTAINER_REGISTRY_AUTHFILE')
        if not authfile:
            bb.fatal("CONTAINER_REGISTRY_AUTH_MODE='authfile' requires CONTAINER_REGISTRY_AUTHFILE")
        if not os.path.exists(authfile):
            bb.fatal(f"Auth file not found: {authfile}")
        return ['--dest-authfile', authfile]

    if auth_mode == 'credsfile':
        credsfile = d.getVar('CONTAINER_REGISTRY_CREDSFILE')
        if not credsfile:
            bb.fatal("CONTAINER_REGISTRY_AUTH_MODE='credsfile' requires CONTAINER_REGISTRY_CREDSFILE")
        if not os.path.exists(credsfile):
            bb.fatal(f"Credentials file not found: {credsfile}")

        creds = _container_registry_parse_credsfile(credsfile)

        # Token takes precedence
        if 'CONTAINER_REGISTRY_TOKEN' in creds:
            return ['--dest-registry-token', creds['CONTAINER_REGISTRY_TOKEN']]

        username = creds.get('CONTAINER_REGISTRY_USER')
        password = creds.get('CONTAINER_REGISTRY_PASSWORD')
        if username and password:
            return ['--dest-creds', f'{username}:{password}']

        bb.fatal("Credentials file must contain CONTAINER_REGISTRY_TOKEN or both "
                 "CONTAINER_REGISTRY_USER and CONTAINER_REGISTRY_PASSWORD")

    bb.fatal(f"Unknown CONTAINER_REGISTRY_AUTH_MODE: {auth_mode} "
             "(use 'none', 'home', 'authfile', or 'credsfile')")

def container_registry_generate_tags(d, image_name):
    """Generate tags based on CONTAINER_REGISTRY_TAG_STRATEGY.

    Strategies:
        timestamp - YYYYMMDD-HHMMSS format
        sha/git   - Short git hash if in git repo
        branch    - Git branch name (sanitized: / and _ become -)
        semver    - Nested SemVer tags from PV (1.2.3 -> 1.2.3, 1.2, 1)
        version   - PV from recipe (single tag, not nested)
        latest    - Always includes 'latest' tag
        arch      - Appends architecture suffix to other tags

    Returns list of tags to apply.
    """
    import datetime
    import subprocess

    strategy = (d.getVar('CONTAINER_REGISTRY_TAG_STRATEGY') or 'latest').split()
    tags = []

    for strat in strategy:
        if strat == 'timestamp':
            ts = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
            tags.append(ts)
        elif strat in ('git', 'sha'):
            try:
                git_hash = subprocess.check_output(
                    ['git', 'rev-parse', '--short', 'HEAD'],
                    stderr=subprocess.DEVNULL,
                    cwd=d.getVar('TOPDIR')
                ).decode().strip()
                if git_hash:
                    tags.append(git_hash)
            except (subprocess.CalledProcessError, FileNotFoundError):
                pass
        elif strat == 'branch':
            try:
                branch = subprocess.check_output(
                    ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
                    stderr=subprocess.DEVNULL,
                    cwd=d.getVar('TOPDIR')
                ).decode().strip()
                if branch and branch != 'HEAD':
                    # Sanitize: feature/login -> feature-login
                    safe_branch = branch.replace('/', '-').replace('_', '-')
                    tags.append(safe_branch)
            except (subprocess.CalledProcessError, FileNotFoundError):
                pass
        elif strat == 'semver':
            pv = d.getVar('PV') or ''
            # Strip any suffix like +gitAUTOINC+xxx
            pv = pv.split('+')[0]
            parts = pv.split('.')
            if len(parts) >= 1 and parts[0].isdigit():
                if len(parts) >= 3:
                    tags.append('.'.join(parts[:3]))  # 1.2.3
                if len(parts) >= 2:
                    tags.append('.'.join(parts[:2]))  # 1.2
                tags.append(parts[0])                  # 1
        elif strat == 'version':
            pv = d.getVar('PV')
            if pv and pv != '1.0':
                # Strip suffix for cleaner tag
                pv = pv.split('+')[0]
                tags.append(pv)
        elif strat == 'latest':
            tags.append('latest')
        elif strat == 'arch':
            arch = d.getVar('TARGET_ARCH') or d.getVar('BUILD_ARCH')
            if arch:
                # Add arch suffix to existing tags
                arch_tags = [f"{t}-{arch}" for t in tags if t != 'latest']
                tags.extend(arch_tags)

    # Ensure at least one tag
    if not tags:
        tags = ['latest']

    return tags

def container_registry_push(d, oci_path, image_name, tags=None):
    """Push an OCI image to the configured registry.

    Args:
        d: BitBake datastore
        oci_path: Path to OCI directory (containing index.json)
        image_name: Name for the image (without registry/namespace)
        tags: Optional list of tags (default: generated from strategy)

    Returns:
        List of pushed image references (registry/namespace/name:tag)
    """
    import os
    import subprocess

    registry = d.getVar('CONTAINER_REGISTRY_URL')
    namespace = d.getVar('CONTAINER_REGISTRY_NAMESPACE')
    tls_verify = d.getVar('CONTAINER_REGISTRY_TLS_VERIFY')

    # Find skopeo in native sysroot
    staging_sbindir = d.getVar('STAGING_SBINDIR_NATIVE')
    skopeo = os.path.join(staging_sbindir, 'skopeo')

    if not os.path.exists(skopeo):
        bb.fatal(f"skopeo not found at {skopeo} - ensure skopeo-native is built")

    # Validate OCI directory
    index_json = os.path.join(oci_path, 'index.json')
    if not os.path.exists(index_json):
        bb.fatal(f"Invalid OCI directory: {oci_path} (missing index.json)")

    # Generate tags if not provided
    if tags is None:
        tags = container_registry_generate_tags(d, image_name)

    pushed = []
    src = f"oci:{oci_path}"

    secure_mode = d.getVar('CONTAINER_REGISTRY_SECURE') == '1'
    storage = d.getVar('CONTAINER_REGISTRY_STORAGE')

    for tag in tags:
        dest = f"docker://{registry}/{namespace}/{image_name}:{tag}"

        cmd = [skopeo, 'copy']

        # TLS handling: secure mode uses CA cert, insecure mode disables verification
        if secure_mode:
            pki_dir = os.path.join(storage, 'pki')
            if os.path.exists(os.path.join(pki_dir, 'ca.crt')):
                cmd.extend(['--dest-cert-dir', pki_dir])
            else:
                bb.warn(f"Secure mode enabled but CA cert not found at {pki_dir}/ca.crt")
                bb.warn("Run 'container-registry.sh start' to generate PKI infrastructure")
                cmd.append('--dest-tls-verify=false')
        elif tls_verify == 'false':
            cmd.append('--dest-tls-verify=false')

        # Add authentication arguments if configured
        auth_args = _container_registry_get_auth_args(d)
        cmd.extend(auth_args)

        cmd.extend([src, dest])

        bb.note(f"Pushing {image_name}:{tag} to {registry}/{namespace}/")

        try:
            subprocess.check_call(cmd)
            pushed.append(f"{registry}/{namespace}/{image_name}:{tag}")
            bb.note(f"Successfully pushed {dest}")
        except subprocess.CalledProcessError as e:
            bb.error(f"Failed to push {dest}: {e}")

    return pushed

def container_registry_discover_oci_images(d):
    """Discover OCI images in the deploy directory.

    Finds directories matching *-oci or *-latest-oci patterns
    that contain valid OCI layouts (index.json).

    Returns:
        List of tuples: (oci_path, image_name)
    """
    import os

    deploy_dir = d.getVar('DEPLOY_DIR_IMAGE')
    if not deploy_dir or not os.path.isdir(deploy_dir):
        return []

    images = []

    for entry in os.listdir(deploy_dir):
        # Match *-oci or *-latest-oci directories
        if not (entry.endswith('-oci') or entry.endswith('-latest-oci')):
            continue

        oci_path = os.path.join(deploy_dir, entry)
        if not os.path.isdir(oci_path):
            continue

        # Verify valid OCI layout
        if not os.path.exists(os.path.join(oci_path, 'index.json')):
            continue

        # Extract image name from directory name
        # container-base-qemux86-64.rootfs-20260108.rootfs-oci -> container-base
        # container-base-latest-oci -> container-base
        name = entry
        for suffix in ['-latest-oci', '-oci']:
            if name.endswith(suffix):
                name = name[:-len(suffix)]
                break

        # Remove machine suffix if present (e.g., -qemux86-64)
        machine = d.getVar('MACHINE')
        if machine and f'-{machine}' in name:
            name = name.split(f'-{machine}')[0]

        # Remove rootfs timestamp suffix (e.g., .rootfs-20260108)
        if '.rootfs-' in name:
            name = name.split('.rootfs-')[0]

        images.append((oci_path, name))

    return images
