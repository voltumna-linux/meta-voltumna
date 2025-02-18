include edt-pdv.inc

DEPENDS = "jpeg tiff"

SRC_URI:append = " \
	file://makefiles.patch \
	"

PARALLEL_MAKE = ""

do_compile() {
	oe_runmake -C ${S}/pdv libpdv.so
}

do_install () {
	install -d ${D}${includedir} ${D}${libdir}
	for f in `${CC} -M -MM ${S}/pdv/libpdv.h | cut -d: -f2-`
	do
		test -f $f && install -m 0644 "$f" ${D}${includedir}
	done
	install -m 0644 ${S}/pdv/libpdv.so ${D}${libdir}/libpdv.so.${PV}
	ln -sfrn ${D}${libdir}/libpdv.so.${PV} ${D}${libdir}/libpdv.so
	ln -sfrn ${D}${libdir}/libpdv.so.${PV} ${D}${libdir}/libpdv.so.5
}

BBCLASSEXTEND = "nativesdk"
