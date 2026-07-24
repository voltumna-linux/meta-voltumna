SUMMARY = "Autostart test container"
DESCRIPTION = "A container for testing autostart functionality. \
Runs a simple service that logs timestamps continuously."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

# Inherit from container-app-base for standard container setup
require recipes-extended/images/container-app-base.bb

# The test service that runs continuously
CONTAINER_APP = "autostart-test"
CONTAINER_APP_CMD = "/usr/bin/autostart-test"

# To test autostart, add to local.conf:
#   BUNDLED_CONTAINERS = "autostart-test-container-latest-oci:docker:autostart"
#
# Then verify on target:
#   docker ps                    # Should show container running
#   docker logs autostart-test-container  # Should show timestamp logs
#
# For Podman:
#   BUNDLED_CONTAINERS = "autostart-test-container-latest-oci:podman:autostart"
#   podman ps
#   podman logs autostart-test-container
