DESCRIPTION = "A3818 PCI Express CONET2 Controller"
HOMEPAGE = "https://www.caen.it/products/a3818/"
LICENSE = "CLOSED"

inherit native

SRC_URI = " \
	file://A3818Drv-${PV}.tar.gz \
	"

S = "${WORKDIR}/A3818Drv-${PV}"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
	install -d ${D}${includedir}
	install -m 0644 ${S}/include/a3818.h ${D}${includedir}
}
