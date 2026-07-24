SUMMARY = "Yocto Project builder container with systemd"
DESCRIPTION = "A self-hosting Yocto build container. Includes compiler \
    toolchain, Python 3, Git, and all tools needed to compile the Yocto \
    Project. Uses systemd init and supports CROPS-style dynamic user \
    creation for volume-mounted builds."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

IMAGE_FSTYPES = "container oci"
inherit image
inherit image-oci

# Multi-layer OCI image
OCI_LAYER_MODE = "multi"
OCI_LAYERS = "\
    systemd-base:packages:packagegroup-yocto-builder-base \
    build-tools:packages:packagegroup-yocto-builder-toolchain \
    yocto-extras:packages:packagegroup-yocto-builder-extras \
"

# Entrypoint: user setup script -> systemd
OCI_IMAGE_ENTRYPOINT = "/usr/bin/builder-entry.sh"

# OCI metadata
OCI_IMAGE_AUTHOR ?= "meta-virtualization"
OCI_IMAGE_TAG ?= "latest"

# All packages listed here to trigger builds (multi-layer requirement)
IMAGE_INSTALL = "packagegroup-yocto-builder"

# No kernel needed for container
IMAGE_CONTAINER_NO_DUMMY = "1"

# Minimize image
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"
