# example-container-bundle_1.0.bb
# ===========================================================================
# Example container bundle recipe demonstrating container-bundle.bbclass
# ===========================================================================
#
# This recipe shows how to create a package that bundles containers.
# When installed via IMAGE_INSTALL, the containers are automatically
# merged into the target image's container storage.
#
# Usage in image recipe (e.g., container-image-host.bb):
#   IMAGE_INSTALL += "example-container-bundle"
#
# Or in local.conf (use pn- override for specific images):
#   IMAGE_INSTALL:append:pn-container-image-host = " example-container-bundle"
#
# IMPORTANT: Do NOT use global IMAGE_INSTALL:append without pn- override!
# This causes circular dependencies when container images try to include
# the bundle that depends on them.
#
# ===========================================================================

SUMMARY = "Example container bundle"
DESCRIPTION = "Demonstrates container-bundle.bbclass by bundling the \
               container-base image. Use this as a template for your \
               own container bundles."
HOMEPAGE = "https://github.com/anthropics/meta-virtualization"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit container-bundle

# Define containers to bundle
# Format: source[:autostart-policy]
#
# source: Either a local recipe name or registry URL
#   - Local: "container-base" (simple recipe name)
#   - Remote: "docker.io/library/alpine:3.19" (registry URL)
#
# autostart: (optional) autostart | always | unless-stopped | on-failure
#
# Runtime is determined automatically from CONTAINER_PROFILE (or CONTAINER_BUNDLE_RUNTIME)

# Bundle the test containers we've been using:
# - container-base: minimal busybox container
# - container-app-base: busybox with app structure
# - autostart-test-container: container that logs startup for autostart testing
CONTAINER_BUNDLES = "\
    container-base \
    container-app-base \
    autostart-test-container:autostart \
"

# Override runtime if needed (uncomment to force a specific runtime):
# CONTAINER_BUNDLE_RUNTIME = "podman"

# For remote containers (not used in this example), you MUST provide digests:
# CONTAINER_DIGESTS[docker.io/library/redis:7] = "sha256:e422889e156e..."
#
# Get the digest with:
#   skopeo inspect docker://docker.io/library/redis:7 | jq -r '.Digest'

# Example with multiple containers and autostart:
# CONTAINER_BUNDLES = "\
#     myapp:autostart \
#     mydb \
#     docker.io/library/redis:7 \
# "
# CONTAINER_DIGESTS[docker.io/library/redis:7] = "sha256:e422889..."
