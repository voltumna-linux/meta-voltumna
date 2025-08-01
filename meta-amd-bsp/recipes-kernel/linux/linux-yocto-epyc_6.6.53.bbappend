
FILESEXTRAPATHS:prepend := "${THISDIR}/linux-amd-6.6.53:"

require linux-amd-6.6.53.inc
FILES:${KERNEL_PACKAGE_NAME}-modules += "/boot"
FILES:${KERNEL_PACKAGE_NAME}-modules += "/lib/modules/${KERNEL_VERSION}/modules*"
PACKAGES =+ "extra-modules"

LINUX_VERSION_EXTENSION = "-amd-${LINUX_KERNEL_TYPE}"

KERNEL_EXTRA_FEATURES ?= "features/netfilter/netfilter.scc \
                            features/security/security.scc"

KERNEL_FEATURES:append = " ${KERNEL_EXTRA_FEATURES}"
ERROR_QA:remove = "version-going-backwards"