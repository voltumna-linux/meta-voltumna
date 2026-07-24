# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# packagegroup-container-demo.bb
# Build aggregate for all demo containers and bundles
#
# Usage: bitbake packagegroup-container-demo
#
# This triggers builds of all demo containers, test containers, and bundles.
# Use this to build everything needed for container demonstrations.

SUMMARY = "Build all demo containers and bundles"
DESCRIPTION = "Aggregate recipe to build all container demo recipes including \
               OCI images, bundles, and test containers."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# This is a build-only aggregate - no actual package is created
ALLOW_EMPTY:${PN} = "1"
EXCLUDE_FROM_WORLD = "1"

inherit packagegroup

# All OCI container images
CONTAINER_IMAGES = "\
    container-base \
    app-container \
    app-container-alpine \
    app-container-curl \
    app-container-layered \
    app-container-multilayer \
    autostart-test-container \
"

# All container bundles
CONTAINER_BUNDLES = "\
    example-container-bundle \
    remote-container-bundle \
    multilayer-container-bundle \
    alpine-oci-base \
"

# Build dependencies for images
do_build[depends] += "${@' '.join(['%s:do_image_complete' % x for x in d.getVar('CONTAINER_IMAGES').split()])}"

# Build dependencies for bundles
do_build[depends] += "${@' '.join(['%s:do_build' % x for x in d.getVar('CONTAINER_BUNDLES').split()])}"
