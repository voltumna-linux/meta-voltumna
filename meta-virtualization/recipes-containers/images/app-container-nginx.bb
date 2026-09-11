SUMMARY = "Base NGINX container image for development"
DESCRIPTION = "OCI container with NGINX web server."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

# Multi-layer mode: create explicit layers instead of single rootfs layer
OCI_LAYER_MODE = "multi"

# Optional 'dev' mode:
#   - adds a shell to the container
#   - runs the container as root (UID 0)
# Enable with: PACKAGECONFIG:pn-app-container-nginx = "dev"
PACKAGECONFIG ??= ""
PACKAGECONFIG[dev] = ""
inherit container-dev-mode
NONROOT_USER = "nginx"

OCI_IMAGE_APP_RECIPE = "nginx"

# Define layers: each layer contains specific packages
# Format: "name:type:content" where content uses + as delimiter for multiple items
OCI_LAYERS = "\
    base:packages:base-files+base-passwd+netbase \
    ${@bb.utils.contains('PACKAGECONFIG', 'dev', 'shell:packages:${CONTAINER_SHELL}', '', d)} \
    nginx:packages:nginx \
    nginx-dirs:directories:${localstatedir}/log/nginx+/run/nginx+${localstatedir}/volatile/tmp+${localstatedir}/volatile/log \
"

# nginx runs as the nonroot user (uid 65532) and must own the dirs it writes.
# The OCI_LAYERS 'directories:'/'files:' types create paths but drop ownership
# (cp -a --no-preserve=ownership), so they land root-owned and nginx can't
# write them. NONROOT_OWNED_DIRS re-creates them in the nonroot raw layer with
# correct ownership. Mirrors dhi.io/nginx (debian-13/stable.yaml): run, log,
# cache and the default html dir.
NONROOT_OWNED_DIRS = "\
    /run/nginx \
    ${localstatedir}/log/nginx \
    ${localstatedir}/cache/nginx \
    ${datadir}/nginx/html \
"
# Use CMD so `docker run image /bin/sh` works as expected
OCI_IMAGE_CMD = ""

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

OCI_IMAGE_ENTRYPOINT = "/usr/sbin/nginx"
OCI_IMAGE_ENTRYPOINT_ARGS = "-g 'daemon off; error_log stderr notice;'"
OCI_IMAGE_PORTS = "80/tcp"
OCI_IMAGE_TAG = "latest"

SKIP_RECIPE[app-container-nginx] ?= "${@bb.utils.contains('BBFILE_COLLECTIONS', 'webserver', '', 'Depends on meta-webserver which is not included', d)}"
