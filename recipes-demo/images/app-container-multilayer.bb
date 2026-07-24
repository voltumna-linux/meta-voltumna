SUMMARY = "Multi-layer Application container - test OCI_LAYERS"
DESCRIPTION = "Demonstrates OCI_LAYER_MODE = 'multi' with explicit layer definitions"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

# Multi-layer mode: create explicit layers instead of single rootfs layer
OCI_LAYER_MODE = "multi"

# Define layers: each layer contains specific packages
# Format: "name:type:content" where content uses + as delimiter for multiple items
OCI_LAYERS = "\
    base:packages:base-files+base-passwd+netbase \
    shell:packages:busybox \
    app:packages:curl \
"

# Use CMD so `docker run image /bin/sh` works as expected
OCI_IMAGE_CMD = "/bin/sh -c 'echo Hello from multi-layer container && curl --version'"

IMAGE_FSTYPES = "container oci"
inherit image
inherit image-oci

IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

# IMAGE_INSTALL triggers package builds via do_rootfs recrdeptask.
# Even for multi-layer mode, list packages here to ensure they're built.
# The PM will install them directly to layers from DEPLOY_DIR_IPK.
# Note: IMAGE_ROOTFS is still created but ignored for packages layers.
IMAGE_INSTALL = "base-files base-passwd netbase busybox curl"

# Allow build with or without a specific kernel
IMAGE_CONTAINER_NO_DUMMY = "1"

# Note: No ROOTFS_POSTPROCESS_COMMAND needed - IMAGE_ROOTFS is empty
# and PM handles installation directly to OCI layers
