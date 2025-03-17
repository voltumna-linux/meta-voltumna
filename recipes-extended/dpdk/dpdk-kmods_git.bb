SUMMARY = "DPDK Kernel Module igb_uio"
DESCRIPTION = "UIO driver for Intel IGB PCI cards"
HOMEPAGE = "http://git.dpdk.org/dpdk-kmods/"

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://igb_uio.c;beginline=1;endline=4;md5=a05cd72f85021e22ff6b2632b437450b"

SRC_URI = "git://dpdk.org/git/dpdk-kmods;protocol=https;branch=main \
           file://fix-build-with-5-18-kernel.patch;patchdir=../.. \
           "
SRCREV = "e13d7af77a1bf98757f85c3c4083f6ee6d0d2372"

S = "${WORKDIR}/git/linux/igb_uio"

PV = "1.0"

inherit module

EXTRA_OEMAKE += "KSRC='${STAGING_KERNEL_DIR}'"

do_install() {
    if [ -e "${S}/igb_uio.ko" ]
    then
        install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/drivers/net/
        install -m 0644 ${S}/igb_uio.ko ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/drivers/net/
    fi
}
