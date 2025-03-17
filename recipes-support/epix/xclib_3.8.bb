DESCRIPTION = "Library of board control functions."
HOMEPAGE = "https://www.epixinc.com/support/files.php"
LICENSE = "CLOSED"

SRC_URI = " \
        https://www.elettra.eu/images/Documents/Voltumna/intranet/predownloaded-tarballs/xcliblnx_x86_64.tar.gz \
	"
SRC_URI[sha256sum] = "064aa33947177dbf27688b9faa392ab701cafb7d28f32223a4d2a876a92bed77"

COMPATIBLE_HOST = "x86_64.*-linux"

do_install:append() {
	install -d ${D}${includedir} ${D}${datadir}/doc/${BPN} \
		${D}${datadir}/${BPN} ${D}${libdir}
	install -m 0644 ${S}/inc/* ${D}${includedir}
	install -m 0644 ${S}/doc/* ${D}${datadir}/doc/${BPN}
	cp -r ${S}/examples ${D}${datadir}/${BPN}
	install -m 0755 ${S}/lib/xclib_x86_64.so ${D}${libdir}/libxclib.so.${PV}
	ln -srf ${D}${libdir}/libxclib.so.${PV} ${D}${libdir}/libxclib.so.3
	ln -srf ${D}${libdir}/libxclib.so.3 ${D}${libdir}/libxclib.so
}

BBCLASSEXTEND = "nativesdk"
