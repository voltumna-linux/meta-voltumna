DESCRIPTION = "Pesp image creation & manipulation library."
HOMEPAGE = "https://gitlab.elettra.eu/cs/lib/libhimage"
LICENSE = "CLOSED"

SRCREV = "dde641b425306af58fcd8770cb6bafebd96c7adf"
SRC_URI = "git://gitlab.elettra.eu/cs/lib/libhimage.git;protocol=https;branch=master"

S = "${WORKDIR}/git"

do_install () {
	install -d ${D}${includedir} ${D}${libdir}
	cp -r ${S}/include/* ${D}${includedir}
	cp -r ${S}/lib/* ${D}${libdir}
}

PARALLEL_MAKE = ""

BBCLASSEXTEND = "nativesdk"
