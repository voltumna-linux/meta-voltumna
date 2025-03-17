FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI += " \
	file://resize-helper \
	"

do_install_append() {
	# Fix permission bits
	chmod 0644 ${D}${sysconfdir}/udev/rules.d/*.rules

	# Replace rezie-helper
   	install -m 0755 ${WORKDIR}/resize-helper ${D}${sbindir}
}
