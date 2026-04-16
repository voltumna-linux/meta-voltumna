DESCRIPTION = "Artesyn Linux kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

LINUX_VERSION ?= "5.10"
LINUX_VERSION_EXTENSION ?= "-artesyn"

SRCREV ?= "1bc794de78433edcb5d004d4fd2c14b2be79597d"
KBRANCH ?= "artesyn-${LINUX_VERSION}"
SRC_URI = "git://github.com/voltumna-linux/linux-artesyn.git;protocol=https;branch=${KBRANCH}"

PV = "${LINUX_VERSION}.252+git${SRCPV}"

COMPATIBLE_MACHINE = "(mvme2500|mvme5100|mvme6100|mvme7100)"

DEPENDS:append:mvme2500 = "u-boot-mkimage-native"

# How handle in-kernel configurations which uses config fragments?
# KBUILD_DEFCONFIG_mvme5100 ?= "mvme5100_defconfig"
# KBUILD_DEFCONFIG_mvme2500 ?= "mpc85xx_defconfig"
# KCONFIG_MODE ?= "--alldefconfig"

SRC_URI:append = " \
	file://defconfig \
	file://enable_compat_time.cfg \
	"

SRC_URI:append:mvme5100 = " \
	file://altivec.cfg \
	file://devtmpfs.cfg \
	"

SRC_URI:append:mvme6100 = " \
	file://altivec.cfg \
	file://devtmpfs.cfg \
        "

SRC_URI:append:mvme7100 = " \
	file://altivec.cfg \
	file://devtmpfs.cfg \
	"

SRC_URI:append:mvme2500 = " \
	file://devtmpfs.cfg \
	file://enable-pci-realloc.cfg \
	"

require recipes-kernel/linux/linux-yocto.inc
