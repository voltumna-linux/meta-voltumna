# multilayer-container-bundle_1.0.bb
# ===========================================================================
# Bundle for multi-layer OCI container demonstration
# ===========================================================================
#
# This recipe bundles app-container-multilayer, which demonstrates
# OCI_LAYER_MODE = "multi" with explicit layer definitions.
#
# Usage in local.conf:
#   IMAGE_INSTALL:append:pn-container-image-host = " multilayer-container-bundle"
#
# ===========================================================================

SUMMARY = "Multi-layer container bundle"
DESCRIPTION = "Bundles app-container-multilayer to demonstrate multi-layer \
               OCI images with container-cross-install."
HOMEPAGE = "https://github.com/anthropics/meta-virtualization"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit container-bundle

# Bundle the multi-layer demo container
# This container has 3 layers: base, shell, app
CONTAINER_BUNDLES = "\
    app-container-multilayer \
"
