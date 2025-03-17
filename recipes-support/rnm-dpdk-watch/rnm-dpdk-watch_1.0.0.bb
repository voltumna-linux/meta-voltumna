DESCRIPTION = "The watch utility for rnm-dpdk"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=d34e694e6b747fedea3fd4a1c406f217"

DEPENDS:append = "librnmdpdk"

SRC_URI = "https://gitlab.elettra.eu/cs/util/rnm-dpdk-watch/-/archive/${PV}/rnm-dpdk-watch-${PV}.tar.bz2"
SRC_URI[sha256sum] = "8cd29aa086d2582d6695dc35423d6fc36299293b7e3d683bfe168d94c68d8140"

do_install() {
	oe_runmake PREFIX=${D}/usr install
}

PARALLEL_MAKE = ""
