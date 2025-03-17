include andor3.inc

DEPENDS += "libusb-compat curl numactl"
DEPENDS:class-nativesdk += "libusb-compat curl"
RDEPENDS:${PN} += "libbitflow"

INSANE_SKIP:${PN} += "already-stripped"

PACKAGES += " ${BPN}-examples"
FILES:${PN}-examples += "${datadir}/${BPN}/examples"

FILES:${PN} += " \
	${sysconfdir}/apogee \
	${sysconfdir}/udev/rules.d \
	${libdir}/lib*gcc52*.so \
	"

FILES:${PN}-dev:remove = "${libdir}/lib*.so"
FILES:${PN}-dev:append = " ${libdir}/libat*.so ${libdir}/libat*.so.3"

do_install() {
 	install -d ${D}${includedir}/GenAPIinc
 	install -m 0644 ${S}/inc/* ${D}${includedir}
	cp -r ${S}/GenAPIinc/* ${D}${includedir}/GenAPIinc

 	install -d ${D}${libdir}
	install -m 0755 ${S}/x86_64/GenAPI/lib* ${D}${libdir}
	for l in `ls ${S}/x86_64/lib*`
	do
		libfile=`basename ${l}`
		install -m 0755 ${S}/x86_64/${libfile} ${D}${libdir}
		libname=`echo ${libfile} | sed -n "s,\(.*\).so.*,\1,p"`
		libversion=`echo ${libfile} | sed -n "s,.*.so.\(.*\),\1,p"`
		ln -sfrn ${D}${libdir}/${libfile} ${D}${libdir}/${libname}.so
		ln -sfrn ${D}${libdir}/${libfile} ${D}${libdir}/${libname}.so.3
	done
 	
	install -d ${D}${docdir}/${BPN}
	cp -r ${S}/doc/* ${D}${docdir}/${BPN}/
	
	install -d ${D}${datadir}/${BPN}/examples
	cp -r ${S}/examples/* ${D}${datadir}/${BPN}/examples

	tar zxf ${S}/etc-Apogee-camera.tgz -C ${WORKDIR} --strip-components 2
	install -d ${D}${sysconfdir}/apogee/camera
	install -m 0644 ${WORKDIR}/camera/* ${D}${sysconfdir}/apogee/camera
 
	install -d ${D}${sysconfdir}/udev/rules.d/
	install -m 0644 ${S}/etc/*.rules ${D}${sysconfdir}/udev/rules.d/
}

BBCLASSEXTEND = "nativesdk"
