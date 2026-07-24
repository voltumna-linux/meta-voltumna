# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# container-oci-registry-config.bb
# ===========================================================================
# Configure custom container registry for OCI runtimes (OPT-IN)
# ===========================================================================
#
# FOR OCI-COMPATIBLE RUNTIMES (use /etc/containers/registries.conf.d/):
#   - Podman
#   - Skopeo
#   - Buildah
#   - CRI-O
#
# NOT FOR DOCKER - Docker uses /etc/docker/daemon.json
#   See: docker-registry-config.bb for Docker configuration
#
# This recipe creates a drop-in configuration file for accessing a custom
# container registry. It supports both insecure (HTTP) and secure (HTTPS with TLS)
# modes. It is completely OPT-IN and does not modify any existing configuration files.
#
# IMPORTANT: This recipe:
#   - Does NOT modify docker-distribution or container-host-config
#   - Does NOT clobber public registry access (docker.io, quay.io, etc.)
#   - Uses drop-in files in /etc/containers/registries.conf.d/
#   - Skips entirely if CONTAINER_REGISTRY_URL is not set
#   - In secure mode: installs CA cert to /etc/containers/certs.d/{registry}/
#
# Usage:
#   # Insecure mode (HTTP):
#   CONTAINER_REGISTRY_URL = "localhost:5000"
#   CONTAINER_REGISTRY_INSECURE = "1"
#   IMAGE_FEATURES += "container-registry"
#
#   # Secure mode (HTTPS with TLS):
#   CONTAINER_REGISTRY_SECURE = "1"
#   CONTAINER_REGISTRY_URL = "localhost:5000"
#   IMAGE_FEATURES += "container-registry"
#
#   The IMAGE_FEATURES mechanism auto-selects this recipe for Podman/CRI-O
#   or docker-registry-config for Docker based on VIRTUAL-RUNTIME_container_engine.
#
# ===========================================================================

SUMMARY = "Configure custom container registry for Podman/Skopeo/Buildah (opt-in)"
DESCRIPTION = "Adds drop-in configuration for Podman, Skopeo, Buildah, and CRI-O. \
NOT for Docker (use docker-registry-config for Docker). \
Supports both insecure (HTTP) and secure (HTTPS with TLS) modes. \
Does NOT modify existing registries.conf - creates a separate file in \
registries.conf.d/ that is merged at runtime. Public registries remain accessible. \
This recipe is opt-in: requires CONTAINER_REGISTRY_URL to be set. \
Use IMAGE_FEATURES container-registry to auto-select based on container engine."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit allarch container-registry

# User MUST set these - recipe skips otherwise
CONTAINER_REGISTRY_SEARCH_FIRST ?= "1"

# Path to OCI auth config (for baked credentials)
# NOT stored in bitbake - should point to external file
CONTAINER_REGISTRY_AUTHFILE ?= ""

# OCI runtime configuration for Podman
# Runtime name (e.g. "vxn") — creates a containers.conf.d drop-in
PODMAN_OCI_RUNTIME ?= ""
# Path to OCI runtime binary (e.g. "/usr/bin/vxn-oci-runtime")
PODMAN_OCI_RUNTIME_PATH ?= ""

# Skip recipe entirely if not configured
# User must explicitly set CONTAINER_REGISTRY_URL to enable
python() {
    registry = d.getVar('CONTAINER_REGISTRY_URL')
    oci_runtime = (d.getVar('PODMAN_OCI_RUNTIME') or "").strip()
    if not registry and not oci_runtime:
        raise bb.parse.SkipRecipe("No registry or OCI runtime configured - recipe is opt-in only")

    # Check for conflicting settings
    secure = d.getVar('CONTAINER_REGISTRY_SECURE') == '1'
    insecure = d.getVar('CONTAINER_REGISTRY_INSECURE') == '1'

    if secure and insecure:
        bb.fatal("CONTAINER_REGISTRY_SECURE='1' and CONTAINER_REGISTRY_INSECURE='1' cannot both be set. "
                 "Use secure mode (TLS+auth) OR insecure mode (HTTP), not both.")

    # In secure mode, depend on PKI generation
    if secure:
        d.appendVarFlag('do_install', 'depends', ' container-registry-index:do_generate_registry_script')
}

python do_install() {
    import os
    import shutil

    registry = d.getVar('CONTAINER_REGISTRY_URL')
    insecure = d.getVar('CONTAINER_REGISTRY_INSECURE') == "1"
    secure = d.getVar('CONTAINER_REGISTRY_SECURE') == "1"
    search_first = d.getVar('CONTAINER_REGISTRY_SEARCH_FIRST') == "1"
    ca_cert = d.getVar('CONTAINER_REGISTRY_CA_CERT')
    authfile = d.getVar('CONTAINER_REGISTRY_AUTHFILE') or ''
    oci_runtime = (d.getVar('PODMAN_OCI_RUNTIME') or "").strip()
    oci_runtime_path = (d.getVar('PODMAN_OCI_RUNTIME_PATH') or "").strip()

    dest = d.getVar('D')

    # --- Registry configuration ---
    if registry:
        # Extract registry host (strip any path)
        registry_host = registry.split('/')[0] if '/' in registry else registry

        confdir = os.path.join(dest, d.getVar('sysconfdir').lstrip('/'),
                               'containers', 'registries.conf.d')
        os.makedirs(confdir, exist_ok=True)

        # Install CA cert in secure mode
        if secure:
            if os.path.exists(ca_cert):
                cert_dir = os.path.join(dest, 'etc/containers/certs.d', registry_host)
                os.makedirs(cert_dir, exist_ok=True)
                shutil.copy(ca_cert, os.path.join(cert_dir, 'ca.crt'))
                bb.note("Installed CA certificate for registry: %s" % registry_host)
            else:
                bb.warn("Secure mode enabled but CA certificate not found at %s" % ca_cert)
                bb.warn("Run 'container-registry.sh start' to generate PKI, then rebuild this package")

        # In secure mode, insecure should be false
        if secure:
            insecure = False

        # Generate drop-in config
        config_path = os.path.join(confdir, '50-custom-registry.conf')

        with open(config_path, 'w') as f:
            f.write("# Custom container registry: %s\n" % registry)
            f.write("# Generated by container-oci-registry-config recipe\n")
            f.write("# This is ADDITIVE - base registries.conf is unchanged\n")
            f.write("# Public registries (docker.io, quay.io) remain accessible\n")
            f.write("#\n")
            if secure:
                f.write("# Mode: secure (TLS with CA certificate verification)\n")
                f.write("# CA cert: /etc/containers/certs.d/%s/ca.crt\n" % registry_host)
            else:
                f.write("# Mode: insecure (HTTP or untrusted TLS)\n")
            f.write("#\n")
            f.write("# To remove: uninstall container-oci-registry-config package\n")
            f.write("# or delete this file\n\n")

            if search_first:
                f.write("# Search this registry for unqualified image names\n")
                f.write('unqualified-search-registries = ["%s"]\n\n' % registry)

            f.write('[[registry]]\n')
            f.write('location = "%s"\n' % registry_host)
            if insecure:
                f.write('insecure = true\n')
            else:
                f.write('insecure = false\n')

        mode = "secure" if secure else ("insecure" if insecure else "default")
        bb.note("Created registry config for %s (mode=%s)" % (registry, mode))

    # --- OCI runtime configuration ---
    if oci_runtime:
        dropin_dir = os.path.join(dest, d.getVar('sysconfdir').lstrip('/'),
                                  'containers', 'containers.conf.d')
        os.makedirs(dropin_dir, exist_ok=True)

        runtime_path = oci_runtime_path if oci_runtime_path else "/usr/bin/%s" % oci_runtime
        dropin_path = os.path.join(dropin_dir, '50-oci-runtime.conf')

        with open(dropin_path, 'w') as f:
            f.write("# OCI runtime configuration\n")
            f.write("# Generated by container-oci-registry-config recipe\n\n")
            f.write("[engine]\n")
            f.write('runtime = "%s"\n\n' % oci_runtime)
            f.write("[engine.runtimes]\n")
            f.write('%s = ["%s"]\n' % (oci_runtime, runtime_path))

        bb.note("Created OCI runtime drop-in for %s (%s)" % (oci_runtime, runtime_path))

    # Install authfile if provided (for baked credentials)
    if authfile and os.path.exists(authfile):
        containers_dir = os.path.join(dest, 'etc/containers')
        os.makedirs(containers_dir, exist_ok=True)
        auth_json = os.path.join(containers_dir, 'auth.json')
        shutil.copy(authfile, auth_json)
        os.chmod(auth_json, 0o600)
        bb.note("Installed OCI auth config from %s" % authfile)
}

FILES:${PN} = " \
    ${sysconfdir}/containers/registries.conf.d \
    ${sysconfdir}/containers/containers.conf.d \
    ${sysconfdir}/containers/certs.d/*/ca.crt \
    ${sysconfdir}/containers/auth.json \
"

# Ensure proper permissions on auth file
pkg_postinst:${PN}() {
#!/bin/sh
if [ -f $D/etc/containers/auth.json ]; then
    chmod 600 $D/etc/containers/auth.json
fi
}

# Soft dependency - works with or without container-host-config
# If container-host-config is installed, our drop-in extends it
RRECOMMENDS:${PN} = "container-host-config"
