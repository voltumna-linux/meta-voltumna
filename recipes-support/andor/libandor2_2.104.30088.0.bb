include andor2.inc

DEPENDS = "libusb-compat"

SRC_URI:append = " \
	file://90-andor.rules  \
	file://90-shamrock.rules \
	"

PACKAGES += " ${BPN}-examples"
FILES:${PN}-examples += "${datadir}/andor2/examples"

FILES:${PN} += " \
	${libdir}/firmware/andor \
	${sysconfdir}/udev/rules.d \
	"

do_install () {
 	install -d ${D}${includedir} ${D}${libdir}
 	install -m 0644 ${S}/include/* ${D}${includedir}
	for p in `ls ${S}/lib/lib*x86_64*${PV}`
	do
		n=`basename $p | sed -n "s,\(.*\)-x86_64.so.${PV},\1,p"`
	 	lib="${n}-x86_64.so.${PV}"
	 	install -m 0644 ${S}/lib/${lib} ${D}${libdir}
	 	ln -sfrn ${D}${libdir}/$lib ${D}${libdir}/$n.so
	 	ln -sfrn ${D}${libdir}/$lib ${D}${libdir}/$n.so.2
	done
 	
	install -d ${D}${docdir}/andor2
	cp -r ${S}/doc/* ${D}${docdir}/andor2/
	
	install -d ${D}${datadir}/andor2/examples
	cp -r ${S}/examples/console/* ${D}${datadir}/andor2/examples
 
	install -d ${D}${libdir}/firmware/andor
	cp -r ${S}/etc/* ${D}${libdir}/firmware/andor/
 
	install -d ${D}${sysconfdir}/udev/rules.d/
	install -m 0644 ${WORKDIR}/*.rules ${D}${sysconfdir}/udev/rules.d/
}

BBCLASSEXTEND = "nativesdk"
