DESCRIPTION = "Basler's Pylon camera software"
HOMEPAGE = "https://www.baslerweb.com/en/sales-support/downloads/software-downloads/#type=pylonsoftware;language=all;version=all"
LICENSE = "CLOSED"

BUILDNUMBER="19861"
SRC_URI = " \
	file://${DL_DIR}/pylon_${PV}.${BUILDNUMBER}_x86_64.tar.gz;subdir=${BPN}-${PV} \
	"
SRC_URI[sha256sum] = "f82e402e9c3d5630e535439c5d12a2fe156f3ed4399e579403fe253717401316"
COMPATIBLE_HOST = "x86_64.*-linux"
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT  = "1"

# PACKAGES = "libpylon libpylon-dev pylon-tools"
PACKAGES = "libpylon libpylon-dev"

# FILES:pylon-tools = "${bindir} ${datadir}"
FILES:libpylon-dev = "${includedir} ${libdir}/libbxapi.so \
		${libdir}/libgxapi.so ${libdir}/libpylonbase.so \
		${libdir}/libpylonc.so ${libdir}/libpylon_TL_bcon.so \
		${libdir}/libpylon_TL_camemu.so ${libdir}/libpylon_TL_gige.so \
		${libdir}/libpylon_TL_gtc.so ${libdir}/libpylon_TL_usb.so \
		${libdir}/libpylonutility.so ${libdir}/libuxapi.so"
FILES:libpylon = "${libdir}/*${PV}.so ${libdir}/*v3_1*.so ${libdir}/pylon-libusb-1.0.so"

do_install () {
#	install -d ${D}${bindir}
#	cp -dR bin/* ${D}${bindir}
	
#	install -d ${D}${datadir}
#	cp -dR share/* ${D}${datadir}

	install -d ${D}${includedir}
	cp -dR include/* ${D}${includedir}

	install -d ${D}${libdir}
	cp -dR lib/*.so ${D}${libdir}
}

BBCLASSEXTEND = "nativesdk"
