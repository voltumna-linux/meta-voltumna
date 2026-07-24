SUMMARY = "Systemd system container for ${SYSTEMD_CONTAINER_APP}"
DESCRIPTION = "A small systemd system container which will run \
                ${SYSTEMD_CONTAINER_APP}."

SYSTEMD_CONTAINER_APP ?= ""

# Use local.conf to specify the application(s) to install
IMAGE_INSTALL += "${SYSTEMD_CONTAINER_APP}"

# To mask additional systemd services, use:
#   CONTAINER_SYSTEMD_MASK:pn-container-systemd-config:append = " extra.service"
# in local.conf or your image recipe.

require container-systemd-base.inc
