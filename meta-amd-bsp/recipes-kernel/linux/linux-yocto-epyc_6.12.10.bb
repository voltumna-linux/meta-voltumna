

KBRANCH ?= "linux-6.12.y"
require recipes-kernel/linux/linux-yocto.inc

SRCREV_meta = "5d9c6c5b0531161f9e8e9d108740ebcec9177398"
SRCREV_machine = "a6ad5510dbb5f55cd2d1b44b11a18120bf79a5a3"
INC_PR := "r1"

SRC_URI = "git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git;protocol=https;name=machine;branch=${KBRANCH}; \
	git://git.yoctoproject.org/yocto-kernel-cache;type=kmeta;name=meta;branch=yocto-6.12;destsuffix=yocto-kmeta"

LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

LINUX_VERSION ?= "6.12.10"
KMETA = "kernel-meta"
KCONF_BSP_AUDIT_LEVEL = "1"

PV = "6.12.10"
KERNEL_VERSION_SANITY_SKIP = "1"

PR := "${INC_PR}.0"

KMACHINE = "common-pc-64"
COMPATIBLE_MACHINE = "${MACHINE}"



