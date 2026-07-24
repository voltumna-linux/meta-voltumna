SUMMARY = "Multi-architecture OCI container base image"
DESCRIPTION = "Builds container-base for multiple architectures and \
combines them into a single OCI Image Index (manifest list)."
LICENSE = "MIT"

inherit oci-multiarch

OCI_MULTIARCH_RECIPE = "container-base"
OCI_MULTIARCH_PLATFORMS = "aarch64 x86_64"
