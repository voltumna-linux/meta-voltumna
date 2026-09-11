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

# Note: no IMAGE_INSTALL needed for the packages listed above.
# image-oci.bbclass walks OCI_LAYERS at parse time and folds every
# package named in a ":packages:" layer into IMAGE_INSTALL automatically,
# so do_rootfs's recrdeptask builds them. A recipe only needs to set
# IMAGE_INSTALL itself for packages that are NOT named in any layer
# (e.g. packages consumed only by a rootfs postprocess fixup).

# Use CMD so `docker run image /bin/sh` works as expected
OCI_IMAGE_CMD = "/bin/sh -c 'echo Hello from multi-layer container && curl --version'"

IMAGE_FSTYPES = "container oci"
inherit image
inherit image-oci

IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

# Allow build with or without a specific kernel
IMAGE_CONTAINER_NO_DUMMY = "1"

# Note: No ROOTFS_POSTPROCESS_COMMAND needed - IMAGE_ROOTFS is empty
# and PM handles installation directly to OCI layers
