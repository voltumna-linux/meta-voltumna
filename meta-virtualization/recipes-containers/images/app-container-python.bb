SUMMARY = "Base python3 container image"
DESCRIPTION = "OCI container image running Python with non-root user. \
\
In 'dev' mode, can optionally run as 'root' and add 'pip' to allow \
developers to simply run 'pip install' on top of this container (Not \
advised for production/hardened use)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

# Multi-layer mode: create explicit layers instead of single rootfs layer
OCI_LAYER_MODE = "multi"

# Optional 'dev' mode:
#   - adds a shell to the container
#   - adds python3-pip to the python layer (enables `pip install` at runtime)
#   - runs the container as root (UID 0) so pip can write to site-packages
# Enable with: PACKAGECONFIG:pn-app-container-python = "dev"
PACKAGECONFIG ??= ""
PACKAGECONFIG[dev] = ""
inherit container-dev-mode

# Define layers: each layer contains specific packages
# Format: "name:type:content" where content uses + as delimiter for multiple items
OCI_LAYERS = "\
    base:packages:base-files+base-passwd+netbase \
    ${@bb.utils.contains('PACKAGECONFIG', 'dev', 'shell:packages:${CONTAINER_SHELL}', '', d)} \
    terminal:packages:ncurses-terminfo-base \
    python:packages:python3+coreutils${@bb.utils.contains('PACKAGECONFIG', 'dev', '+python3-pip', '', d)} \
"

# Use CMD so `docker run image /bin/sh` works as expected
OCI_IMAGE_CMD = "python3"

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
