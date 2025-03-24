SUMMARY = "LibDAQ: The Data AcQuisition Library"
DESCRIPTION = "LibDAQ is a pluggable abstraction layer for interacting with a data source (traditionally a network interface or network data plane)."
HOMEPAGE = "http://www.snort.org"
SECTION = "libs"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=79258250506422d064560a7b95b2d53e"

DEPENDS = "libdnet libpcap"

inherit autotools pkgconfig

SRC_URI = "git://github.com/snort3/libdaq.git;protocol=https;branch=master \
           file://0001-example-Use-lm-for-the-fst-module.patch"

SRCREV = "fc6f7d729b5ab65081abd3811dcd79a91c463b37"

S = "${WORKDIR}/git"

FILES:${PN} += "${libdir}/daq/*.so"
