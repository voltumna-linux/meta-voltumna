# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vpdmn-rootfs-image.bb
# Minimal Podman-capable image for vpdmn QEMU environment
#
# This image is built via multiconfig and used by vpdmn-initramfs-create
# to provide a proper rootfs for running Podman in QEMU.
#
# Build with:
#   bitbake mc:vruntime-aarch64:vpdmn-rootfs-image
#   bitbake mc:vruntime-x86-64:vpdmn-rootfs-image

SUMMARY = "Minimal Podman rootfs for vpdmn"
DESCRIPTION = "A minimal image containing Podman tools for use with vpdmn. \
               This image runs inside QEMU to provide Podman command execution."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Track init script changes via file-checksums
# This adds the file content hash to the task signature
do_rootfs[file-checksums] += "${THISDIR}/files/vpdmn-init.sh:True"
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

# We need Podman and container tools
# Podman is daemonless - no containerd required!
# Note: crun is explicitly listed because vruntime distro sets
# VIRTUAL-RUNTIME_container_runtime="" to avoid runc/crun conflicts.
# Note: skopeo is required inside the guest for batch import
# (skopeo copy oci:... containers-storage:...).
IMAGE_INSTALL = " \
    packagegroup-core-boot \
    podman \
    crun \
    skopeo \
    conmon \
    cni \
    busybox \
    iproute2 \
    iptables \
    util-linux \
    ca-certificates \
"

# No extra features needed
IMAGE_FEATURES = ""

# Keep the image small
IMAGE_ROOTFS_SIZE = "524288"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# Use squashfs for smaller size (~3x compression)
# The preinit mounts squashfs read-only with tmpfs overlay for writes
IMAGE_FSTYPES = "squashfs"

# Install our init script
ROOTFS_POSTPROCESS_COMMAND += "install_vpdmn_init;"

install_vpdmn_init() {
    # Install vpdmn-init.sh as /init and vcontainer-init-common.sh alongside it
    install -m 0755 ${THISDIR}/files/vpdmn-init.sh ${IMAGE_ROOTFS}/init
    install -m 0755 ${THISDIR}/files/vcontainer-init-common.sh ${IMAGE_ROOTFS}/vcontainer-init-common.sh

    # Install vxn-init.sh for Xen backend (selected via vcontainer.init=/vxn-init.sh)
    install -m 0755 ${THISDIR}/files/vxn-init.sh ${IMAGE_ROOTFS}/vxn-init.sh

    # Create required directories
    install -d ${IMAGE_ROOTFS}/mnt/input
    install -d ${IMAGE_ROOTFS}/mnt/state
    install -d ${IMAGE_ROOTFS}/var/lib/containers
    install -d ${IMAGE_ROOTFS}/run/containers

    # Create skopeo/podman policy
    install -d ${IMAGE_ROOTFS}/etc/containers
    echo '{"default":[{"type":"insecureAcceptAnything"}]}' > ${IMAGE_ROOTFS}/etc/containers/policy.json

    # Create registries.conf for podman
    cat > ${IMAGE_ROOTFS}/etc/containers/registries.conf << 'EOF'
# Search registries
unqualified-search-registries = ["docker.io", "quay.io"]

# Short name aliases
[aliases]
"alpine" = "docker.io/library/alpine"
"busybox" = "docker.io/library/busybox"
"nginx" = "docker.io/library/nginx"
"ubuntu" = "docker.io/library/ubuntu"
"debian" = "docker.io/library/debian"
EOF

    # Create storage.conf for podman
    # IMPORTANT: Must use VFS driver, not overlay, because:
    # - The storage tar is extracted into Yocto rootfs under pseudo (fakeroot)
    # - Overlay storage has special files/symlinks that fail under pseudo
    # - VFS extracts cleanly (simpler structure, no special filesystem features)
    install -d ${IMAGE_ROOTFS}/etc/containers/storage.conf.d
    cat > ${IMAGE_ROOTFS}/etc/containers/storage.conf << 'EOF'
[storage]
driver = "vfs"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options]
additionalimagestores = []
EOF

    # Create containers.conf for podman engine settings
    # Use CNI instead of netavark — netavark's dependency chain
    # (nmap → libpcap → bluez5 → python3-pygobject → cairo) is too
    # heavy for the vruntime BBMASK environment.
    cat > ${IMAGE_ROOTFS}/etc/containers/containers.conf << 'EOF'
[network]
network_backend = "cni"
cni_plugin_dirs = ["/opt/cni/bin", "/usr/libexec/cni"]
EOF

    # Prevent libnss_systemd segfaults — systemd is not running in the
    # vruntime VM (busybox init), but libnss_systemd.so is installed as
    # a dependency. Override nsswitch.conf to use only files/compat.
    cat > ${IMAGE_ROOTFS}/etc/nsswitch.conf << 'EOF'
passwd:     files
group:      files
shadow:     files
hosts:      files dns
networks:   files
protocols:  files
services:   files
ethers:     files
rpc:        files
EOF
}
