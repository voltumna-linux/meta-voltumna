# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# docker-registry-config.bb
# ===========================================================================
# Configure custom container registry for Docker daemon (OPT-IN)
# ===========================================================================
#
# FOR DOCKER ONLY - creates /etc/docker/daemon.json
#
# NOT for Podman/Skopeo/Buildah - they use /etc/containers/registries.conf.d/
#   See: container-oci-registry-config.bb for Podman/Skopeo/Buildah
#
# This recipe creates daemon.json for Docker to access registries.
# It supports both insecure (HTTP) and secure (HTTPS with TLS) modes.
#
# NOTE: Docker does not support "default registry" like our vdkr transform.
# Users must still use fully qualified image names unless using Docker Hub.
#
# IMPORTANT: This recipe:
#   - Skips entirely if neither insecure nor secure registry is configured
#   - Creates /etc/docker/daemon.json
#   - In secure mode: installs CA cert to /etc/docker/certs.d/{registry}/
#   - In insecure mode: adds registry to insecure-registries list
#
# Usage:
#   # Insecure mode (HTTP):
#   DOCKER_REGISTRY_INSECURE = "10.0.2.2:5000 myregistry.local:5000"
#   IMAGE_FEATURES += "container-registry"
#
#   # Secure mode (HTTPS with TLS):
#   CONTAINER_REGISTRY_SECURE = "1"
#   CONTAINER_REGISTRY_URL = "localhost:5000"
#   IMAGE_FEATURES += "container-registry"
#
#   The IMAGE_FEATURES mechanism auto-selects this recipe for Docker
#   or container-oci-registry-config for Podman/CRI-O based on
#   VIRTUAL-RUNTIME_container_engine.
#
# ===========================================================================

SUMMARY = "Configure container registry for Docker daemon (opt-in)"
DESCRIPTION = "Creates /etc/docker/daemon.json with registry config. \
FOR DOCKER ONLY - not for Podman/Skopeo (use container-oci-registry-config for those). \
Supports both insecure (HTTP) and secure (HTTPS with TLS) modes. \
Use IMAGE_FEATURES container-registry to auto-select based on container engine."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit allarch container-registry

# Space-separated list of insecure registries
# Example: "10.0.2.2:5000 myregistry.local:5000"
# Can also use runtime-agnostic CONTAINER_REGISTRY_URL + CONTAINER_REGISTRY_INSECURE
DOCKER_REGISTRY_INSECURE ?= ""

# Path to Docker auth config (for baked credentials)
# NOT stored in bitbake - should point to external file
CONTAINER_REGISTRY_AUTHFILE ?= ""

# OCI runtime configuration for Docker daemon
# JSON object mapping runtime names to paths, e.g.:
#   DOCKER_OCI_RUNTIMES = '{"vxn": {"path": "/usr/bin/vxn-oci-runtime"}}'
DOCKER_OCI_RUNTIMES ?= ""
# Default OCI runtime name (must be a key in DOCKER_OCI_RUNTIMES or "runc")
DOCKER_DEFAULT_RUNTIME ?= ""

def get_insecure_registries(d):
    """Get insecure registries from either Docker-specific or generic config"""
    # Prefer explicit DOCKER_REGISTRY_INSECURE if set
    docker_insecure = d.getVar('DOCKER_REGISTRY_INSECURE') or ""
    if docker_insecure.strip():
        return docker_insecure.strip()
    # Fall back to CONTAINER_REGISTRY_URL if marked insecure
    registry_url = d.getVar('CONTAINER_REGISTRY_URL') or ""
    is_insecure = d.getVar('CONTAINER_REGISTRY_INSECURE') or ""
    if registry_url.strip() and is_insecure in ['1', 'true', 'yes']:
        return registry_url.strip()
    return ""

def is_secure_mode(d):
    """Check if secure registry mode is enabled"""
    return d.getVar('CONTAINER_REGISTRY_SECURE') == '1'

# Skip recipe entirely if not configured
python() {
    secure = is_secure_mode(d)
    registries = get_insecure_registries(d)

    # Check for conflicting settings
    if secure and registries:
        bb.fatal("CONTAINER_REGISTRY_SECURE='1' conflicts with insecure registry settings. "
                 "Use secure mode (TLS+auth) OR insecure mode (HTTP), not both.")

    oci_runtimes = (d.getVar('DOCKER_OCI_RUNTIMES') or "").strip()

    if not secure and not registries and not oci_runtimes:
        raise bb.parse.SkipRecipe("No registry or OCI runtime configured - recipe is opt-in only")

    # In secure mode, depend on PKI generation
    if secure:
        d.appendVarFlag('do_install', 'depends', ' container-registry-index:do_generate_registry_script')
}

python do_install() {
    import os
    import json
    import shutil

    dest = d.getVar('D')
    confdir = os.path.join(dest, d.getVar('sysconfdir').lstrip('/'), 'docker')
    os.makedirs(confdir, exist_ok=True)

    secure = is_secure_mode(d)
    registries = get_insecure_registries(d).split()
    ca_cert = d.getVar('CONTAINER_REGISTRY_CA_CERT')
    registry_url = d.getVar('CONTAINER_REGISTRY_URL') or ''
    authfile = d.getVar('CONTAINER_REGISTRY_AUTHFILE') or ''

    config = {}

    if secure:
        # Secure mode: install CA cert, no insecure-registries
        # Translate localhost/127.0.0.1 to 10.0.2.2 for QEMU slirp networking
        qemu_url = registry_url.replace('localhost', '10.0.2.2').replace('127.0.0.1', '10.0.2.2')
        registry_host = qemu_url.split('/')[0] if '/' in qemu_url else qemu_url

        if os.path.exists(ca_cert):
            # Install CA cert to /etc/docker/certs.d/{registry}/ca.crt
            cert_dir = os.path.join(dest, 'etc/docker/certs.d', registry_host)
            os.makedirs(cert_dir, exist_ok=True)
            shutil.copy(ca_cert, os.path.join(cert_dir, 'ca.crt'))
            bb.note(f"Installed CA certificate for registry: {registry_host}")
        else:
            bb.warn(f"Secure mode enabled but CA certificate not found at {ca_cert}")
            bb.warn("Run 'container-registry.sh start' to generate PKI, then rebuild this package")

        # daemon.json can be empty or minimal in secure mode
        # (no insecure-registries needed when using TLS)
        bb.note("Secure mode: Docker will use TLS verification with installed CA cert")
    else:
        # Insecure mode: add to insecure-registries
        if registries:
            config["insecure-registries"] = registries
            bb.note(f"Created Docker config with insecure registries: {registries}")

    # OCI runtime configuration
    oci_runtimes = (d.getVar('DOCKER_OCI_RUNTIMES') or "").strip()
    default_runtime = (d.getVar('DOCKER_DEFAULT_RUNTIME') or "").strip()

    if oci_runtimes:
        config["runtimes"] = json.loads(oci_runtimes)
        bb.note("Added OCI runtimes to Docker config: %s" % oci_runtimes)
    if default_runtime:
        config["default-runtime"] = default_runtime
        bb.note("Set default Docker runtime: %s" % default_runtime)

    # Install authfile if provided (for baked credentials)
    if authfile and os.path.exists(authfile):
        docker_dir = os.path.join(dest, 'root/.docker')
        os.makedirs(docker_dir, mode=0o700, exist_ok=True)
        config_json = os.path.join(docker_dir, 'config.json')
        shutil.copy(authfile, config_json)
        os.chmod(config_json, 0o600)
        bb.note(f"Installed Docker auth config from {authfile}")

    # Write daemon.json (may be empty in secure mode)
    config_path = os.path.join(confdir, 'daemon.json')
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
        f.write("\n")
}

FILES:${PN} = " \
    ${sysconfdir}/docker/daemon.json \
    ${sysconfdir}/docker/certs.d/*/ca.crt \
    /root/.docker/config.json \
"

# Ensure proper permissions on auth file
pkg_postinst:${PN}() {
#!/bin/sh
if [ -f $D/root/.docker/config.json ]; then
    chmod 600 $D/root/.docker/config.json
fi
}

# Docker must be installed for this to be useful
RDEPENDS:${PN} = "docker"
