include hamamatsu.inc

do_unpack[depends] += "p7zip-native:do_populate_sysroot"

DEPENDS = "libusb-compat firebird-utils"

SRC_URI:append = " \
	https://www.hamamatsu.com/content/dam/hamamatsu-photonics/sites/static/sys/dcam-sdk/Hamamatsu_DCAMSDK4_v24026764.7z;name=sdk \
	file://90-hamamatsu.rules \
	"

SRC_URI[sdk.sha256sum] = "5aa7cbe2ad4c585d5dc613afd42d04aa0b600dcdc88e59c1e0f6540ea07093ec"

COMPATIBLE_HOST = "x86_64.*-linux"
HAMAMATSU_DIR = "${libdir}/api"

FILES:${PN} += " \
	${sbindir} \
	${libdir} \
	${sysconfdir}/udev/rules.d \
	"

INSANE_SKIP:${PN} += "dev-so libdir"

do_install() {
	install -d ${D}${docdir}/${BPN} ${D}${libdir} \
		${D}${includedir} ${D}${datadir}/${BPN} \ 
		${D}${sysconfdir}/udev/rules.d/ ${D}${sbindir} \
		${D}${sysconfdir}/ld.so.conf.d ${D}${sysconfdir}/modules \
		${D}${HAMAMATSU_DIR}/modules ${D}${sysconfdir}/aslphx/

	echo "${HAMAMATSU_DIR}" > ${D}${sysconfdir}/ld.so.conf.d/hamamatsu.conf
	echo "${HAMAMATSU_DIR}/modules" >> ${D}${sysconfdir}/ld.so.conf.d/hamamatsu.conf

	# From API
	install -m 0644 ${WORKDIR}/DCAM-API_Lite*/doc/* ${D}${docdir}/${BPN}

        install -m 0644 ${WORKDIR}/DCAM-API_Lite*/api/runtime/x86_64/core/libdcamapi* \
            ${D}${HAMAMATSU_DIR}
	ln -sr ${D}${HAMAMATSU_DIR}/libdcamapi* ${D}${HAMAMATSU_DIR}/libdcamapi.so.4
	ln -sr ${D}${HAMAMATSU_DIR}/libdcamapi.so.4 ${D}${libdir}/libdcamapi.so

	for l in ${WORKDIR}/DCAM-API_Lite*/api/runtime/x86_64/core/libdcamdig* \
		${WORKDIR}/DCAM-API_Lite*/api/runtime/x86_64/usb3/lib* \
		${WORKDIR}/DCAM-API_Lite*/api/runtime/x86_64/fbd/lib*
		do
			f=$(basename $l)
			s1=$(echo $f | cut -d. -f-2)
			s2=$(echo $f | cut -d. -f-3)
			install -m 0644 $l ${D}${HAMAMATSU_DIR}/modules
			ln -sr ${D}${HAMAMATSU_DIR}/modules/$f ${D}${HAMAMATSU_DIR}/modules/$s1
			ln -sr ${D}${HAMAMATSU_DIR}/modules/$f ${D}${HAMAMATSU_DIR}/modules/$s2
		done
	install -m 0644 ${WORKDIR}/DCAM-API_Lite*/api/driver/usb/udev/rules.d/*.rules \
		${D}${sysconfdir}/udev/rules.d/
	install -m 0755 ${WORKDIR}/DCAM-API_Lite*/tools/x86_64/* ${D}${sbindir}
	install -m 0644 ${WORKDIR}/DCAM-API_Lite*/api/runtime/x86_64/core/dcamlog.conf \
		${D}${sysconfdir}
	install -m 0644 ${WORKDIR}/DCAM-API_Lite*/api/runtime/x86_64/fbd/aslphx/* \
		${D}${sysconfdir}/aslphx/
	install -m 0644 ${WORKDIR}/DCAM-API_Lite*/api/runtime/x86_64/core/dcamdig.conf \
		${WORKDIR}/DCAM-API_Lite*/api/runtime/x86_64/fbd/*.conf \
		${WORKDIR}/DCAM-API_Lite*/api/runtime/x86_64/usb3/*.conf \
		${D}${sysconfdir}/modules
	cd ${D}${HAMAMATSU_DIR}; ln -s /etc etc
	
	# From SDK
	install -m 0644 ${WORKDIR}/dcamsdk4/inc/* ${D}${includedir}
	cp -r ${WORKDIR}/dcamsdk4/doc/* ${D}${docdir}/${BPN}
	cp -r ${WORKDIR}/dcamsdk4/samples ${D}${datadir}/${BPN} 
	chmod -R 755 ${D}${datadir}/${BPN} 

	# Additional udev rules
	install -d ${D}${sysconfdir}/udev/rules.d/
	install -m 0644 ${WORKDIR}/90-hamamatsu.rules ${D}${sysconfdir}/udev/rules.d/
}

BBCLASSEXTEND = "nativesdk"
