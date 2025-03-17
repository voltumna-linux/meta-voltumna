DESCRIPTION = "A3818 PCI Express CONET2 Controller"
HOMEPAGE = "https://www.caen.it/products/a3818/"
LICENSE = "CLOSED"

inherit nativesdk

SRC_URI = " \
        https://www.elettra.eu/images/Documents/Voltumna/intranet/A3818Drv-${PV}.tar.gz \
	"
SRC_URI[sha256sum] = "bf32eb92c4c6dc6d007c7b4e83f73e22244c84965094b18e55894c63c0ca3715"
S = "${WORKDIR}/A3818Drv-${PV}"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
	install -d ${D}${includedir}
	install -m 0644 ${S}/include/a3818.h ${D}${includedir}
}
