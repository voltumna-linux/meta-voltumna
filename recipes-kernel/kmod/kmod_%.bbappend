FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append += " \
	file://voltumna.conf \
	"

do_install_append() {
	install -m 0644 ${WORKDIR}/voltumna.conf ${D}${sysconfdir}/depmod.d/
}
