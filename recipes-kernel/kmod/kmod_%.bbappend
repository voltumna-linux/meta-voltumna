FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://voltumna.conf \
       "

do_install:append() {
	install -m 0644 ${WORKDIR}/voltumna.conf ${D}${sysconfdir}/depmod.d/
}

