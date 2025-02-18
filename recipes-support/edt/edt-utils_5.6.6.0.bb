include edt-pdv.inc

SRC_URI:append = " \
	file://makefiles.patch \
	file://90-edt.rules  \
	file://edtmknod \
	"

PARALLEL_MAKE = ""

do_compile() {
	oe_runmake -C ${S}/pdv pciload
}

FILES:${PN} += " \
	${datadir} \
	${sysconfdir}/udev/rules.d \
	${sbindir} \
	"

do_install () {
	install -d ${D}${sysconfdir}/udev/rules.d/
	install -m 0644 ${WORKDIR}/90-edt.rules ${D}${sysconfdir}/udev/rules.d/
    
	install -d ${D}${sbindir}/
	install -m 0755 ${WORKDIR}/edtmknod ${D}${sbindir}/

	install -d ${D}${sbindir} ${D}${datadir}/edt
	install -m 0755 ${S}/pdv/pciload ${D}${sbindir}
	cp -r ${S}/pdv/flash ${D}/${datadir}/edt
}
