# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vdkr-rootfs-image.bb
# Minimal Docker-capable image for vdkr QEMU environment
#
# This image is built via multiconfig and used by vdkr-initramfs-create
# to provide a proper rootfs for running Docker in QEMU.
#
# Build with:
#   bitbake mc:vruntime-aarch64:vdkr-rootfs-image
#   bitbake mc:vruntime-x86-64:vdkr-rootfs-image
#
# Optional baked-in registry defaults (can still be overridden via CLI):
# Uses the same variables as container-registry infrastructure:
#   CONTAINER_REGISTRY_URL = "10.0.2.2:5000"
#   CONTAINER_REGISTRY_NAMESPACE = "yocto"
#   CONTAINER_REGISTRY_INSECURE = "1"  (or DOCKER_REGISTRY_INSECURE)

SUMMARY = "Minimal Docker rootfs for vdkr"
DESCRIPTION = "A minimal image containing Docker tools for use with vdkr. \
               This image runs inside QEMU to provide Docker command execution."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Track init script changes via file-checksums
# This adds the file content hash to the task signature
do_rootfs[file-checksums] += "${THISDIR}/files/vdkr-init.sh:True"
do_rootfs[file-checksums] += "${THISDIR}/files/vcontainer-init-common.sh:True"
do_rootfs[file-checksums] += "${THISDIR}/files/vxn-init.sh:True"

# Force rebuild control:
# Set VCONTAINER_FORCE_BUILD = "1" in local.conf to disable stamp caching
# and force rootfs to always rebuild. Useful when debugging dependency issues.
# Default: use normal stamp caching (file-checksums handles init script changes)
VCONTAINER_FORCE_BUILD ?= ""
python () {
    if d.getVar('VCONTAINER_FORCE_BUILD') == '1':
        d.setVarFlag('do_rootfs', 'nostamp', '1')
}

# Inherit from core-image-minimal for a minimal base
inherit core-image

# We need Docker and container tools
# Note: runc is explicitly listed because vruntime distro sets
# VIRTUAL-RUNTIME_container_runtime="" to avoid runc/crun conflicts.
# Note: skopeo is required inside the guest for batch import
# (skopeo copy oci:... containers-storage:...).
IMAGE_INSTALL = " \
    packagegroup-core-boot \
    docker-moby \
    containerd \
    runc \
    skopeo \
    busybox \
    iproute2 \
    iptables \
    util-linux \
    kernel-modules \
    ca-certificates \
"

# No extra features needed
IMAGE_FEATURES = ""

# Keep the image small
IMAGE_ROOTFS_SIZE = "524288"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# Registry defaults - reuse common container-registry variables
# Empty URL means no baked config (can still configure via CLI)
CONTAINER_REGISTRY_URL ?= ""
CONTAINER_REGISTRY_NAMESPACE ?= "yocto"
CONTAINER_REGISTRY_INSECURE ?= "0"
DOCKER_REGISTRY_INSECURE ?= ""

# Use squashfs for smaller size (~3x compression)
# The preinit mounts squashfs read-only with tmpfs overlay for writes
IMAGE_FSTYPES = "squashfs"

# Install our init script
ROOTFS_POSTPROCESS_COMMAND += "install_vdkr_init;"

install_vdkr_init() {
    # Install vdkr-init.sh as /init and vcontainer-init-common.sh alongside it
    install -m 0755 ${THISDIR}/files/vdkr-init.sh ${IMAGE_ROOTFS}/init
    install -m 0755 ${THISDIR}/files/vcontainer-init-common.sh ${IMAGE_ROOTFS}/vcontainer-init-common.sh

    # Install vxn-init.sh for Xen backend (selected via vcontainer.init=/vxn-init.sh)
    install -m 0755 ${THISDIR}/files/vxn-init.sh ${IMAGE_ROOTFS}/vxn-init.sh

    # Create required directories
    install -d ${IMAGE_ROOTFS}/mnt/input
    install -d ${IMAGE_ROOTFS}/mnt/state
    install -d ${IMAGE_ROOTFS}/var/lib/docker
    install -d ${IMAGE_ROOTFS}/run/containerd

    # Create skopeo policy
    install -d ${IMAGE_ROOTFS}/etc/containers
    echo '{"default":[{"type":"insecureAcceptAnything"}]}' > ${IMAGE_ROOTFS}/etc/containers/policy.json

    # Create baked-in registry config if specified
    # Uses common CONTAINER_REGISTRY_* variables for consistency
    # These defaults can be overridden via kernel cmdline (docker_registry=)
    #
    # NOTE: localhost URLs are auto-translated to 10.0.2.2 for QEMU slirp networking
    # This allows CONTAINER_REGISTRY_URL=localhost:5000 to work for both:
    #   - Host-side operations (registry script, pushing)
    #   - vdkr inside QEMU (via 10.0.2.2 slirp gateway)
    install -d ${IMAGE_ROOTFS}/etc/vdkr
    if [ -n "${CONTAINER_REGISTRY_URL}" ]; then
        cat > ${IMAGE_ROOTFS}/etc/vdkr/registry.conf << 'VDKR_EOF'
# vdkr registry defaults (baked at build time)
# These can be overridden via:
#   - Kernel cmdline: docker_registry=... docker_insecure_registry=...
#   - vdkr CLI: vdkr --registry ... or vdkr vconfig registry ...
VDKR_EOF
        # Build registry URL with namespace
        # Translate localhost to 10.0.2.2 for QEMU slirp networking
        QEMU_REGISTRY_URL=$(echo "${CONTAINER_REGISTRY_URL}" | sed 's/^localhost/10.0.2.2/' | sed 's/^127\.0\.0\.1/10.0.2.2/')
        echo "VDKR_DEFAULT_REGISTRY=\"${QEMU_REGISTRY_URL}/${CONTAINER_REGISTRY_NAMESPACE}\"" >> ${IMAGE_ROOTFS}/etc/vdkr/registry.conf

        # Handle insecure registries - check both DOCKER_REGISTRY_INSECURE and CONTAINER_REGISTRY_INSECURE
        INSECURE_LIST="${DOCKER_REGISTRY_INSECURE}"
        if [ "${CONTAINER_REGISTRY_INSECURE}" = "1" ] && [ -n "${QEMU_REGISTRY_URL}" ]; then
            # Use the QEMU-translated URL for insecure list
            INSECURE_LIST="${INSECURE_LIST} ${QEMU_REGISTRY_URL}"
        fi
        # Also translate any localhost entries in the insecure list
        INSECURE_LIST=$(echo "${INSECURE_LIST}" | sed 's/localhost/10.0.2.2/g' | sed 's/127\.0\.0\.1/10.0.2.2/g')
        if [ -n "${INSECURE_LIST}" ]; then
            echo "VDKR_INSECURE_REGISTRIES=\"${INSECURE_LIST}\"" >> ${IMAGE_ROOTFS}/etc/vdkr/registry.conf
        fi
        bbnote "Created vdkr registry config: ${QEMU_REGISTRY_URL}/${CONTAINER_REGISTRY_NAMESPACE}"
    fi
}
