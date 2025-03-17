DESCRIPTION = "Artesyn Linux kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

LINUX_VERSION ?= "5.10"
LINUX_VERSION_EXTENSION ?= "-artesyn"

SRCREV ?= "179624a57b78c02de833370b7bdf0b0f4a27ca31"
KBRANCH ?= "linux-5.10.y"
SRC_URI = "git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git;protocol=https;branch=${KBRANCH}"

PV = "${LINUX_VERSION}.165+git${SRCPV}"

COMPATIBLE_MACHINE = "(mvme5100|mvme2500|mvme7100)"

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
	file://0001-MVME5100-RTC-patch-for-Linux-3.14.patch \
	file://0002-Add-device-tree-entry-for-rtc.patch \
	file://0003-powerpc-embedded6xx-Make-reboot-works-on-MVME5100.patch \
	"

SRC_URI:append:mvme7100 = " \
	file://altivec.cfg \
	file://devtmpfs.cfg \
	file://0001-Enable-L2-cache-on-all-cores.patch \
	file://0002-Enable-RTC-and-PCI.patch \
	file://0003-Try-to-add-PCI-interrupt-definition.patch \
	"

SRC_URI:append:mvme2500 = " \
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

# EXTRA_OEMAKE:append:mvme2500 = " HAS_BIARCH=n"

require recipes-kernel/linux/linux-yocto.inc
