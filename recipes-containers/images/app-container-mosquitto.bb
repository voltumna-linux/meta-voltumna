SUMMARY = "Mosquitto MQTT broker container image"
DESCRIPTION = "OCI container running the Eclipse Mosquitto MQTT broker \
with standard MQTT (1883) and WebSocket (9001) listeners enabled."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

# Multi-layer mode: create explicit layers instead of single rootfs layer
OCI_LAYER_MODE = "multi"

# Optional 'dev' mode:
#   - adds a shell to the container
#   - runs the container as root (UID 0)
# Enable with: PACKAGECONFIG:pn-app-container-mosquitto = "dev"
PACKAGECONFIG ??= ""
PACKAGECONFIG[dev] = ""
inherit container-dev-mode

# Define layers: each layer contains specific packages
# Format: "name:type:content" where content uses + as delimiter for multiple items
OCI_LAYERS = "\
    base:packages:base-files+base-passwd+netbase \
    ${@bb.utils.contains('PACKAGECONFIG', 'dev', 'shell:packages:${CONTAINER_SHELL}', '', d)} \
    mosquitto:packages:mosquitto \
"

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

OCI_IMAGE_ENTRYPOINT = "${sbindir}/mosquitto"
OCI_IMAGE_ENTRYPOINT_ARGS = "-c '${sysconfdir}/mosquitto/mosquitto.conf'"
OCI_IMAGE_PORTS = "1883/tcp 9001/tcp"
OCI_IMAGE_TAG = "latest"
