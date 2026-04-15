DESCRIPTION = "Artesyn Linux kernel"
LICENSE = "GPLv2"
LIC_FILES_CHKSUM = "file://COPYING;md5=bbea815ee2795b2f4230826c0c6b8814"

LINUX_VERSION ?= "5.4"
LINUX_VERSION_EXTENSION ?= "-artesyn"

SRCREV ?= "7cc086c4bf17f988604c306bb803471d7e727053"
KBRANCH ?= "artesyn-${LINUX_VERSION}"
SRC_URI = "git://github.com/voltumna-linux/linux-artesyn.git;protocol=https;branch=${KBRANCH}"

PV = "${LINUX_VERSION}.193+git${SRCPV}"

COMPATIBLE_MACHINE = "(mvme5100|mvme6100|mvme2500|mvme7100)"

DEPENDS_mvme2500 += "u-boot-mkimage-native"

# How handle in-kernel configurations which uses config fragments?
# KBUILD_DEFCONFIG_mvme5100 ?= "mvme5100_defconfig"
# KBUILD_DEFCONFIG_mvme2500 ?= "mpc85xx_defconfig"
# KCONFIG_MODE ?= "--alldefconfig"

SRC_URI_append += " \
	file://defconfig \
	"

SRC_URI_append_mvme5100 += " \
	file://altivec.cfg \
	file://devtmpfs.cfg \
	"

SRC_URI_append_mvme6100 += " \
	file://altivec.cfg \
	file://devtmpfs.cfg \
	"

SRC_URI_append_mvme7100 += " \
	file://altivec.cfg \
	file://devtmpfs.cfg \
	"

SRC_URI_append_mvme2500 += " \
	file://devtmpfs.cfg \
	file://enable-pci-realloc.cfg \
	"

require recipes-kernel/linux/linux-yocto.inc
