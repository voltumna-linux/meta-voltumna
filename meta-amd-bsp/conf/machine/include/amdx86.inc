PREFERRED_PROVIDER_virtual/kernel ?= "${@bb.utils.contains('RT_KERNEL_AMD', 'yes', "linux-yocto-rt", "linux-yocto", d)}"

require conf/machine/include/amd-common-configurations.inc
include conf/machine/include/amd-customer-configurations.inc

# Add machine specific AMD features and feature pkgs here
DPDK_PKGS = "${@bb.utils.contains("BBFILE_COLLECTIONS", "dpdk", "dpdk dpdk-examples dpdk-tools dpdk-module", "", d)}"

MACHINE_FEATURES:remove = "screen alsa"
MACHINE_EXTRA_RRECOMMENDS:remove = " rtc-test alsa-utils"

# Disable the graphical console when machine does not have a screen.
# This allows the serial console to be used for installation.
APPEND:remove="${@bb.utils.contains('MACHINE_FEATURES', 'screen-console', '', 'console=tty0', d)}"

MACHINEOVERRIDES =. "amd:amdx86:"

# Mask out recipes for packages we do not support for
# amdx86 but may be required by others. Use '|' sign
# between the patterns.
BBMASK = "\
.*/meta-amd/common/recipes-support/libtinyxml\
"
