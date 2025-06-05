DESCRIPTION = "Libbufferrt"
LICENSE = "GPLv3"
LIC_FILES_CHKSUM = "file://LICENSE;md5=e9f7e8627ac433ed277eab45950118e0"

SRC_URI = "https://gitlab.elettra.eu/cs/lib/libbufferrt/-/archive/${PV}/libbufferrt-${PV}.tar.bz2"
SRC_URI[sha256sum] = "afe68adc195d3e12c50b6e85ccf2aa47158b67a23520769ae7e137288f090b85"

do_install() {
	oe_runmake PREFIX=${D}${prefix} install
}

BBCLASSEXTEND = "native nativesdk"
