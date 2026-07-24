# SPDX-License-Identifier: MIT
#
# Alpine OCI base image for use with OCI_BASE_IMAGE
#
# This recipe fetches Alpine Linux from Docker Hub and deploys it to
# DEPLOY_DIR_IMAGE for use as a base layer in multi-layer OCI builds.
#
# Usage in your container recipe:
#   OCI_BASE_IMAGE = "alpine-oci-base"
#   IMAGE_INSTALL = "base-files busybox myapp"
#
# The Alpine layers will be preserved, and your IMAGE_INSTALL packages
# are added as an additional layer on top.

SUMMARY = "Alpine Linux OCI base image"
DESCRIPTION = "Fetches Alpine Linux from Docker Hub for use as an OCI base layer"
HOMEPAGE = "https://alpinelinux.org/"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit container-bundle

# Remote container from Docker Hub
CONTAINER_BUNDLES = "docker.io/library/alpine:3.19"

# REQUIRED: Pinned digest for reproducible builds
# Get with: skopeo inspect docker://docker.io/library/alpine:3.19 | jq -r '.Digest'
CONTAINER_DIGESTS[docker.io_library_alpine_3.19] = "sha256:6baf43584bcb78f2e5847d1de515f23499913ac9f12bdf834811a3145eb11ca1"

# Enable deployment to DEPLOY_DIR_IMAGE for use as OCI base layer
CONTAINER_BUNDLE_DEPLOY = "1"
