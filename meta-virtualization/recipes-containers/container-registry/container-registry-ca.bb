# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# container-registry-ca.bb
# ============================================================================
# Install CA certificate for secure container registry on target images.
#
# This recipe installs the CA certificate generated during
# container-registry-index:do_generate_registry_script to the appropriate
# locations for Docker, Podman/CRI-O, and system trust.
#
# Prerequisites:
#   1. Enable secure mode: CONTAINER_REGISTRY_SECURE = "1"
#   2. PKI is auto-generated when building this package
#
# Usage:
#   IMAGE_INSTALL:append = " container-registry-ca"
#
# Installed files:
#   /etc/docker/certs.d/{registry}/ca.crt        - Docker daemon trust
#   /etc/containers/certs.d/{registry}/ca.crt    - Podman/CRI-O trust
#   /usr/local/share/ca-certificates/container-registry-ca.crt - System trust
#
# ============================================================================

SUMMARY = "CA certificate for secure container registry"
DESCRIPTION = "Installs the CA certificate for TLS verification when pulling from the local container registry"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

inherit container-registry

# Only build if secure mode is enabled
python () {
    secure = d.getVar('CONTAINER_REGISTRY_SECURE')
    if secure != '1':
        raise bb.parse.SkipRecipe("CONTAINER_REGISTRY_SECURE is not '1' - secure mode not enabled")
}

# No source files - we use the generated CA cert
SRC_URI = ""

do_configure[noexec] = "1"
do_compile[noexec] = "1"

# Ensure PKI is generated before we try to install the CA cert
do_install[depends] += "container-registry-index:do_generate_registry_script"

python do_install() {
    import os
    import shutil

    d_dir = d.getVar('D')
    ca_cert = d.getVar('CONTAINER_REGISTRY_CA_CERT')
    registry_url = d.getVar('CONTAINER_REGISTRY_URL')

    # Extract registry host (strip port)
    registry_host = registry_url.split('/')[0] if '/' in registry_url else registry_url

    if not os.path.exists(ca_cert):
        bb.fatal(f"CA certificate not found at {ca_cert}. "
                 "This should have been auto-generated. Check container-registry-index:do_generate_registry_script logs.")

    # Install for Docker: /etc/docker/certs.d/{registry}/ca.crt
    docker_cert_dir = os.path.join(d_dir, 'etc/docker/certs.d', registry_host)
    os.makedirs(docker_cert_dir, exist_ok=True)
    shutil.copy(ca_cert, os.path.join(docker_cert_dir, 'ca.crt'))

    # Install for Podman/CRI-O: /etc/containers/certs.d/{registry}/ca.crt
    containers_cert_dir = os.path.join(d_dir, 'etc/containers/certs.d', registry_host)
    os.makedirs(containers_cert_dir, exist_ok=True)
    shutil.copy(ca_cert, os.path.join(containers_cert_dir, 'ca.crt'))

    # Install for system trust: /usr/local/share/ca-certificates/
    system_ca_dir = os.path.join(d_dir, 'usr/local/share/ca-certificates')
    os.makedirs(system_ca_dir, exist_ok=True)
    shutil.copy(ca_cert, os.path.join(system_ca_dir, 'container-registry-ca.crt'))

    bb.note(f"Installed CA certificate for registry: {registry_host}")
}

# Package files
FILES:${PN} = " \
    ${sysconfdir}/docker/certs.d/*/ca.crt \
    ${sysconfdir}/containers/certs.d/*/ca.crt \
    /usr/local/share/ca-certificates/container-registry-ca.crt \
"

# Run update-ca-certificates after install if available
pkg_postinst:${PN}() {
#!/bin/sh
if [ -x /usr/sbin/update-ca-certificates ]; then
    /usr/sbin/update-ca-certificates 2>/dev/null || true
fi
}

RDEPENDS:${PN} = ""
