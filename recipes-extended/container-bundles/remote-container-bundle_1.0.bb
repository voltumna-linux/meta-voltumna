# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# remote-container-bundle_1.0.bb
# ===========================================================================
# Test recipe for remote container fetching via container-bundle.bbclass
# ===========================================================================
#
# This recipe demonstrates and tests fetching containers from a remote
# registry during the Yocto build. The container is pulled via skopeo
# and bundled into a package that can be installed into target images.
#
# Usage in image recipe:
#   IMAGE_INSTALL += "remote-container-bundle"
#
# Or in local.conf:
#   IMAGE_INSTALL:append:pn-container-image-host = " remote-container-bundle"
#
# The container will be available as "busybox:1.36" in the target's
# Docker/Podman storage after boot.
#
# ===========================================================================

SUMMARY = "Remote container bundle test"
DESCRIPTION = "Tests container-bundle.bbclass remote container fetching. \
               Pulls busybox from docker.io and bundles it for installation."
HOMEPAGE = "https://github.com/anthropics/meta-virtualization"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit container-bundle

# Remote container from Docker Hub
# Using busybox as it's small (~2MB) and available for multiple architectures
CONTAINER_BUNDLES = "\
    docker.io/library/busybox:1.36 \
"

# REQUIRED: Pinned digest for reproducible builds
# Get with: skopeo inspect docker://docker.io/library/busybox:1.36 | jq -r '.Digest'
# Note: This is the multi-arch manifest digest, skopeo will select the correct arch
# Key format: Replace / and : with _ for BitBake variable flag compatibility
CONTAINER_DIGESTS[docker.io_library_busybox_1.36] = "sha256:768e5c6f5cb6db0794eec98dc7a967f40631746c32232b78a3105fb946f3ab83"

# Note: busybox is GPL-licensed, so no LICENSE_FLAGS needed.
# For containers with commercial licenses, you would add:
#   LICENSE_FLAGS:append = " commercial"
# And accept in local.conf:
#   LICENSE_FLAGS_ACCEPTED:append = " commercial"
