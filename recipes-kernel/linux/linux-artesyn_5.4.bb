DESCRIPTION = "Artesyn Linux kernel"
LICENSE = "GPLv2"
LIC_FILES_CHKSUM = "file://COPYING;md5=bbea815ee2795b2f4230826c0c6b8814"

LINUX_VERSION ?= "5.4"
LINUX_VERSION_EXTENSION ?= "-artesyn"

SRCREV ?= "6920e4e219fbd51d4284eaf14f5116f7aa75ee65"
KBRANCH ?= "artesyn-${LINUX_VERSION}"
SRC_URI = "git://github.com/voltumna-linux/linux-artesyn.git;protocol=https;branch=${KBRANCH}"

PV = "${LINUX_VERSION}.193+git${SRCPV}"

COMPATIBLE_MACHINE = "(mvme5100|mvme2500|mvme7100)"

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

SRC_URI_append_mvme7100 += " \
	file://altivec.cfg \
	file://devtmpfs.cfg \
	file://0001-Enable-L2-cache-on-all-cores.patch \
	file://0002-Enable-RTC-and-PCI.patch \
	file://0003-Try-to-add-PCI-interrupt-definition.patch \
	"

SRC_URI_append_mvme2500 += " \
	file://devtmpfs.cfg \
	file://enable-pci-realloc.cfg \
	file://0001-Force-the-right-mcpu.patch \
	file://0002-Fix-an-LBC-window-length.patch \
	file://0003-Add-interrupt-for-temperature-sensor.patch \
	file://0004-Workaround-for-let-VME-grab-the-right-IRQ-0.patch \
	file://0005-Remove-add-empty-lines.patch \
	file://0006-Add-commented-code-of-the-interrupt-handlers-for-IRQ.patch \
	file://0007-The-phy-s-compatible-isn-t-necessary-anymore.patch \
	file://0008-Add-SMP-support.patch \
	file://0009-Add-a-complete-proc-file-for-VME.patch \
	"

require recipes-kernel/linux/linux-yocto.inc
