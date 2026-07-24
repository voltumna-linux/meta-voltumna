# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# packagegroup-container-bundles.bb
# Build aggregate for all container bundle recipes
#
# Usage: bitbake packagegroup-container-bundles
#
# This triggers builds of all container bundles that inherit container-bundle.

SUMMARY = "Build all container bundles"
DESCRIPTION = "Aggregate recipe to build all container bundle recipes. \
               Bundles package OCI images for deployment and cross-install."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# This is a build-only aggregate - no actual package is created
ALLOW_EMPTY:${PN} = "1"
EXCLUDE_FROM_WORLD = "1"

inherit packagegroup

# Container bundles (inherit container-bundle)
# These package OCI images for deployment
CONTAINER_BUNDLES = "\
    example-container-bundle \
    remote-container-bundle \
    multilayer-container-bundle \
    alpine-oci-base \
"

# Build dependencies - triggers builds of all listed bundles
do_build[depends] += "${@' '.join(['%s:do_build' % x for x in d.getVar('CONTAINER_BUNDLES').split()])}"
