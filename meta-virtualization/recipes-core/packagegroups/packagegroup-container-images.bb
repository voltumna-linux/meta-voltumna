# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# packagegroup-container-images.bb
# Build aggregate for all OCI container image recipes
#
# Usage: bitbake packagegroup-container-images
#
# This triggers builds of all container images that inherit image-oci.

SUMMARY = "Build all OCI container images"
DESCRIPTION = "Aggregate recipe to build all OCI container image recipes. \
               These are reference containers for testing and demonstration."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# This is a build-only aggregate - no actual package is created
ALLOW_EMPTY:${PN} = "1"
EXCLUDE_FROM_WORLD = "1"

inherit packagegroup

# OCI container images (inherit image-oci)
# These produce OCI-format container images in deploy/
CONTAINER_IMAGES = "\
    container-base \
    app-container \
    app-container-alpine \
    app-container-curl \
    app-container-layered \
    app-container-multilayer \
"

# Build dependencies - triggers builds of all listed images
do_build[depends] += "${@' '.join(['%s:do_image_complete' % x for x in d.getVar('CONTAINER_IMAGES').split()])}"
