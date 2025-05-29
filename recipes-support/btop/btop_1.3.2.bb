SUMMARY = "Resource monitor that shows usage and stats for processor, memory, disks, network and processes."
HOMEPAGE = "https://github.com/aristocratos/btop"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3b83ef96387f14655fc854ddc3c6bd57"
SECTION = "console/utils"

SRC_URI = "git://github.com/aristocratos/btop.git;protocol=https;branch=main"
SRCREV = "fd2a2acdad6fbaad76846cb5e802cf2ae022d670"

S = "${WORKDIR}/git"

do_install:append() {
    install -d ${D}${bindir} ${D}${datadir}/${BPN}
    install -m 0755 ${S}/bin/btop ${D}${bindir}
    cp -r ${S}/themes ${D}${datadir}/${BPN}
}
