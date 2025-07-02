DESCRIPTION = "Library for rnm-dpdk"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=d65a93982c9fc6a88db9de682b55980d"

DEPENDS:append = "dpdk"

SRCREV = "48a6ff7af010a0b3a609bdc6f22acdbe26505731"
SRC_URI = "git://gitlab.elettra.eu/cs/lib/librnmdpdk.git;protocol=https;branch=master"

do_install() {
	oe_runmake PREFIX=${D}${prefix} install
}

PARALLEL_MAKE = ""

BBCLASSEXTEND = "nativesdk"
