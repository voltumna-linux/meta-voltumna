include hamamatsu.inc

FILES:${PN} = " \
	${sbindir} \
	${libdir}/lib*.so \
	"

FILES:${PN}-dev:remove = "${libdir}/lib*.so"

do_install() {
    cd ${S}/usr/local/activesilicon/
    install -d ${D}${libdir} ${D}${sbindir}
    install -m 0644 lib64/* ${D}${libdir}
    install -m 0755 bin64/* ${D}${sbindir}
}

do_extract_data() {
	cd ${S}; ar -xv ${WORKDIR}/DCAM-API_Lite_for_Linux_v24.4.6764/api/driver/firebird/x86_64/as-fbd-linux-ham_3.2.1-1_amd64.deb
	rm debian-binary
	cd ${S}; tar -zxvf ${S}/control.tar.gz; rm ${S}/control.tar.gz
	cd ${S}; tar -zxvf ${S}/data.tar.gz; rm ${S}/data.tar.gz
}

python do_unpack:append() {
    bb.build.exec_func('do_extract_data', d)
}

BBCLASSEXTEND = "nativesdk"
