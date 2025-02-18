include andor3.inc

SRC_URI:append = " \
	file://bitflow.sh \
	"

INSANE_SKIP:${PN} += "already-stripped"

PACKAGES += " ${BPN}-examples"
FILES:${PN}-examples += "${datadir}/${BPN}/examples"

FILES:${PN} += " \
	${bindir} \
	${libdir} \
	${sysconfdir}/profile.d \
	"

FILES:${PN}-dev:remove = "/usr/lib/lib*.so"

do_install() {
	install -d ${D}${sysconfdir}/andor3
	cp -r ${S}/bitflow/camf ${S}/bitflow/config ${S}/bitflow/fshf \
		${D}${sysconfdir}/andor3

 	install -d ${D}${includedir}
 	install -m 0644 ${S}/bitflow/inc/* ${D}${includedir}

 	install -d ${D}${bindir}
 	install -m 0644 ${S}/bitflow/64b/bin/AxionStats ${S}/bitflow/64b/bin/CytonStats \
	 	${S}/bitflow/64b/bin/SimpleCom ${S}/bitflow/64b/bin/BFLogCollector \
		${S}/bitflow/64b/bin/CI* ${D}${bindir}

 	install -d ${D}${libdir}
	install -m 0755 ${S}/bitflow/64b/lib/libBFSOciLib.*.so ${D}${libdir}

	install -d ${D}${docdir}/${BPN}
	cp -r ${S}/bitflow/README_dist ${D}${docdir}/${BPN}

	install -d ${D}${datadir}/${BPN}/examples
	cp -r ${S}/bitflow/src/* ${D}${datadir}/${BPN}/examples
	
	install -d ${D}${sysconfdir}/profile.d
	install -m 0644 ${WORKDIR}/bitflow.sh ${D}${sysconfdir}/profile.d
}

BBCLASSEXTEND = "nativesdk"
