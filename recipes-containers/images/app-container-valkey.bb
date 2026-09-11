SUMMARY = "Valkey key-value store container image"
DESCRIPTION = "OCI container running the Valkey in-memory key-value \
datastore, a flexible distributed datastore that supports both caching \
and beyond caching workloads."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

# Multi-layer mode: create explicit layers instead of single rootfs layer
OCI_LAYER_MODE = "multi"

# Optional 'dev' mode:
#   - runs the container as root (UID 0)
# Enable with: PACKAGECONFIG:pn-app-container-valkey = "dev"
PACKAGECONFIG ??= ""
PACKAGECONFIG[dev] = ""
inherit container-dev-mode

# Unlike the other app-container-* recipes, valkey always ships a real shell,
# in 'dev' and production alike. container-entrypoint.sh is a #!/bin/sh
# script (upstream-compatible arg handling + umask hardening; see the file
# for details) and requires an interpreter to boot at all — 'no shell in
# production' isn't available here without dropping that script and its
# behavior. Matches DHI's own 'hardened' valkey image (debian-13/9.1.yaml),
# which ships bash for the exact same reason rather than go shell-less.
CONTAINER_SHELL = "busybox"

#  image.bbclass intentionally sets do_fetch, do_unpack and do_install to noexec.
#  We do not want to abuse that isolation, so instead get the file from local
#  tree and install in rootfs postprocess.
ROOTFS_POSTPROCESS_COMMAND:append = " rootfs_install_entrypoint_sh ; "
rootfs_install_entrypoint_sh () {
    install -m 0755 ${THISDIR}/${BPN}/container-entrypoint.sh ${IMAGE_ROOTFS}/${bindir}/
}

# Define layers: each layer contains specific packages
# Format: "name:type:content" where content uses + as delimiter for multiple items
OCI_LAYERS = "\
    base:packages:base-files+base-passwd+netbase \
    shell:packages:${CONTAINER_SHELL} \
    valkey:packages:valkey+tini \
    entrypoint:files:${bindir}/container-entrypoint.sh \
"

# The 'nonroot' user needs permissions on the following directories
NONROOT_OWNED_DIRS = "/data /var/lib/valkey /var/log/valkey /run/valkey"

IMAGE_FSTYPES = "container oci"
inherit image
inherit image-oci
inherit container-nonroot-user
inherit container-volatile-fixup

IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

# Allow build with or without a specific kernel
IMAGE_CONTAINER_NO_DUMMY = "1"

# The stock valkey.conf shipped by meta-oe is tuned for a host install
# (daemonize yes, syslog-enabled yes, bind 127.0.0.1). Most users will
# want to create their own valkey.conf and pass it in to the
# container-entrypoint.sh script
OCI_IMAGE_ENTRYPOINT = "${bindir}/docker-init -- ${bindir}/container-entrypoint.sh"
OCI_IMAGE_CMD = "${bindir}/valkey-server"
OCI_IMAGE_PORTS = "6379/tcp"
OCI_IMAGE_TAG = "latest"
OCI_IMAGE_WORKINGDIR = "/data"
