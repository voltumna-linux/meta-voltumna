inherit features_check
REQUIRED_DISTRO_FEATURES = "vcontainer"


DESCRIPTION += "Enable building the ${MCNAME} multiarch image."
SUMMARY ?= "${MCNAME} multiarch image."
HOMEPAGE ?= "https://www.yoctoproject.org/"
LICENSE ?= "MIT"
LIC_FILES_CHKSUM ?= "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"


CONTAINER_IMAGES ?= "\
    container-base \
    app-container-curl \
    app-container-mosquitto \
    app-container-nginx \
    app-container-python \
    app-container-valkey \
    container-yocto-builder \
"

inherit oci-multiarch

BBCLASSEXTEND = "${@' '.join(['mcextend:'+x for x in d.getVar('CONTAINER_IMAGES').split()])}"

OCI_MULTIARCH_RECIPE = "${MCNAME}"
OCI_MULTIARCH_PLATFORMS = "aarch64 x86_64"

# The MCNAME-empty skip for the base recipe (parsed before mcextend runs)
# is handled inside oci-multiarch.bbclass -- no per-recipe check needed.
