FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://resize-helper \
	"

do_install:append() {
	# Fix permission bits
	chmod 0644 ${D}${sysconfdir}/udev/rules.d/*.rules

	# Replace rezie-helper
  	install -m 0755 ${WORKDIR}/resize-helper ${D}${sbindir}
}
