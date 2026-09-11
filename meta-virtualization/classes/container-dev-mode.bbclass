# Shared 'dev' mode support for containers-library app images.
#
# Enable per recipe with:
#   PACKAGECONFIG:pn-<recipe> = "dev"
#
# 'dev' mode wants a shell; default 'production' intent does not, for
# security purposes. Recipes still choose for themselves where
# CONTAINER_SHELL actually gets consumed (e.g. an OCI_LAYERS 'shell' layer
# gated on PACKAGECONFIG 'dev') and whether 'dev' should also relax
# OCI_IMAGE_RUNTIME_UID to run as root.
#
# Each recipe should set the following, we most likely do not want to set
# at the class level.
# PACKAGECONFIG ??= ""
# PACKAGECONFIG[dev] = ""

# In 'dev' mode, override the nonroot UID inherited from container-nonroot-user
# so the container runs as root.
OCI_IMAGE_RUNTIME_UID = "${@bb.utils.contains('PACKAGECONFIG', 'dev', '0', '${NONROOT_UID}', d)}"

# 'dev' always wins and gets a real shell (busybox), regardless of whether
# production intent (below) was also configured, e.g. in local.conf.
#
# For production, if the following is configured in local.conf (or the
# distro):
#      PACKAGE_EXTRA_ARCHS:append = " container-dummy-provides"
#
# it has been explicitly indicated that we don't want or need a shell, so
# we'll add the dummy provides instead of busybox.
#
# This is required, since there are postinstall scripts in base-files and
# base-passwd that reference /bin/sh and we'll get a rootfs error if
# there's no shell or no dummy provider.
CONTAINER_SHELL ?= "${@bb.utils.contains('PACKAGECONFIG', 'dev', 'busybox', bb.utils.contains('PACKAGE_EXTRA_ARCHS', 'container-dummy-provides', 'container-dummy-provides', 'busybox', d), d)}"
