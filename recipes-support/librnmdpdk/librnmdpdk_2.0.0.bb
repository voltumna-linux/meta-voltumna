DESCRIPTION = "Library for rnm-dpdk"
LICENSE = "GPLv3"
LIC_FILES_CHKSUM = "file://LICENSE;md5=d65a93982c9fc6a88db9de682b55980d"

DEPENDS += "dpdk"

SRC_URI = "https://gitlab.elettra.eu/cs/lib/librnmdpdk/-/archive/${PV}/librnmdpdk-${PV}.tar.bz2"
SRC_URI[sha256sum] = "f232791785f9d5fd40eaf90c65f8232c9950483a7f14a72a95e8211dd6a97edd"

do_install() {
	oe_runmake PREFIX=${D}${prefix} install
}

BBCLASSEXTEND = "native nativesdk"
