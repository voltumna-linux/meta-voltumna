DESCRIPTION = "Interface library for CAEN VME Bridges"
HOMEPAGE = "https://www.caen.it/products/caenvmelib-library/"
LICENSE = "CLOSED"

RDEPENDS:${PN} += "libusb1"

SRC_URI = " \
	file://CAENVMELib-v${PV}.tgz \
	"

S = "${WORKDIR}/CAENVMELib-v${PV}"

COMPATIBLE_HOST = "x86_64.*-linux"
INSANE_SKIP:${PN} += "already-stripped file-rdeps"

do_install() {
	install -d ${D}${includedir} ${D}${libdir}
	install -m 0644 ${S}/include/*.h ${D}${includedir}
	install -m 0755 ${S}/lib/x64/libCAENVME.so.v${PV} ${D}${libdir}
	ln -sfrn ${D}${libdir}/libCAENVME.so.v${PV} ${D}${libdir}/libCAENVME.so
}

BBCLASSEXTEND = "nativesdk"
