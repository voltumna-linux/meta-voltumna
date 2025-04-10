SECTION = "kernel"
SUMMARY = "BeagleBoard.org Linux kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

COMPATIBLE_MACHINE = "beagle.*"

inherit kernel

DEFCONFIG_BUILDER = "${S}/ti_config_fragments/defconfig_builder.sh"
require recipes-kernel/linux/setup-defconfig.inc
require recipes-kernel/linux/ti-kernel.inc

# BB.org hasn't switched to "vendored" DTB layout by default yet
KERNEL_DTBVENDORED = "0"

DEPENDS += "gmp-native libmpc-native"

KERNEL_EXTRA_ARGS += "LOADADDR=${UBOOT_ENTRYPOINT} ${EXTRA_DTC_ARGS}"

S = "${WORKDIR}/git"

# 5.10.168 version for 32-bit
SRCREV:armv7a = "ab3861275e2ed302060f1da6ac507d3a4d5518da"
PV:armv7a = "5.10.168+git${SRCPV}"
BRANCH:armv7a = "v5.10.168-ti-r82"

# 5.10.168 version for 64-bit
SRCREV:aarch64 = "78fd4b16849fa64d757ef7a3cae4919e6b18d04f"
PV:aarch64 = "5.10.168+git${SRCPV}"
BRANCH:aarch64 = "v5.10.168-ti-arm64-r118"

SRC_URI = " \
    git://github.com/beagleboard/linux.git;protocol=https;branch=${BRANCH} \
    file://defconfig \
"
