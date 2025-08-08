DESCRIPTION = "Linux Kernel for Altera SoCFPGA"
LICENSE = "GPL-2.0-only"


KERNEL_REPO ?= "git://github.com/altera-fpga/linux-socfpga.git"
KERNEL_PROT ?= "https"

# Kernel CONFIG_LOCALVERSION
LINUX_VERSION_EXTENSION ?= "-altera"

# Build branch name
LINUX_VERSION_PREFIX ?= "socfpga-"
LINUX_VERSION_SUFFIX ?= ""
LINUX_VERSION ?= "4.0"

SRCREV ?= "${AUTOREV}"
SRCREV_machine ?= "${SRCREV}"
PV = "${LINUX_VERSION}${LINUX_VERSION_SUFFIX}"
PV:append = "+git${SRCPV}"

KBRANCH ?= "${LINUX_VERSION_PREFIX}${LINUX_VERSION}${LINUX_VERSION_SUFFIX}"

SRC_URI = "${KERNEL_REPO};protocol=${KERNEL_PROT};branch=${KBRANCH}"

require recipes-kernel/linux/linux-yocto.inc

KBUILD_DEFCONFIG ?= "socfpga_defconfig"
KCONFIG_MODE ?= "--alldefconfig"

FILESEXTRAPATHS:prepend := "${THISDIR}/config:"

INSANE_SKIP:${PN}-src = "buildpaths"

SRC_URI:append:agilex7_dk_si_agf014ea = " file://jffs2.scc file://gpio_sys.scc file://usb_adapter.scc "
SRC_URI:append:agilex7_dk_si_agf014eb = " file://jffs2.scc file://gpio_sys.scc file://usb_adapter.scc "
SRC_URI:append:agilex7_dk_si_agi027fb = " file://jffs2.scc file://gpio_sys.scc file://usb_adapter.scc "
SRC_URI:append:agilex7_dk_si_agi027fa = " file://jffs2.scc file://gpio_sys.scc file://usb_adapter.scc "
SRC_URI:append:agilex7_dk_si_agi027fc = " file://jffs2.scc file://gpio_sys.scc file://usb_adapter.scc "
SRC_URI:append:agilex7_dk_dev_agf027f1es = " file://jffs2.scc file://gpio_sys.scc file://usb_adapter.scc "
SRC_URI:append:agilex7_dk_dev_agm039fes = " file://jffs2.scc file://gpio_sys.scc file://usb_adapter.scc "
SRC_URI:append:agilex7_dk_dev_agm039fb = " file://jffs2.scc file://gpio_sys.scc file://usb_adapter.scc "
SRC_URI:append:agilex7_dk_dev_agf023fa = " file://jffs2.scc file://gpio_sys.scc file://usb_adapter.scc "
SRC_URI:append:agilex5 = " file://jffs2.scc file://gpio_sys.scc file://agilex5.scc file://usb_adapter.scc "
SRC_URI:append:agilex5_dk_a5e065bb32aes1 = " file://jffs2.scc file://gpio_sys.scc file://agilex5.scc file://usb_adapter.scc "
SRC_URI:append:agilex5_dk_a5e013bb32aesi0 = " file://jffs2.scc file://gpio_sys.scc file://agilex5.scc file://usb_adapter.scc "
SRC_URI:append:agilex5_dk_a5e013bb32aes = " file://jffs2.scc file://gpio_sys.scc file://agilex5.scc file://usb_adapter.scc "
SRC_URI:append:agilex5_dk_a5e013bb32aes_5s = " file://jffs2.scc file://gpio_sys.scc file://agilex5.scc file://usb_adapter.scc "
SRC_URI:append:agilex5_mk_a5e065bb32aes1 = " file://jffs2.scc file://gpio_sys.scc file://agilex5.scc file://usb_adapter.scc "
SRC_URI:append:agilex5_mudv_cvr = " file://jffs2.scc file://gpio_sys.scc file://agilex5.scc file://usb_adapter.scc "
SRC_URI:append:agilex5_mucv = " file://jffs2.scc file://gpio_sys.scc file://agilex5.scc file://usb_adapter.scc "
SRC_URI:append:agilex3 = " file://jffs2.scc file://gpio_sys.scc file://usb_adapter.scc "
SRC_URI:append:stratix10 = " file://jffs2.scc file://gpio_sys.scc file://usb_adapter.scc "
SRC_URI:append:stratix10_htile = " file://jffs2.scc file://gpio_sys.scc file://usb_adapter.scc "
SRC_URI:append:arria10 = " file://lbdaf.scc file://usb_adapter.scc "
SRC_URI:append:cyclone5 = " file://lbdaf.scc file://usb_adapter.scc "
SRC_URI:append:arria5 = " file://lbdaf.scc file://usb_adapter.scc "
SRC_URI:append:n5x = " file://jffs2.scc file://gpio_sys.scc file://usb_adapter.scc "
