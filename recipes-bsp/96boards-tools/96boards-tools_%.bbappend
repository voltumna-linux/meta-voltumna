FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://resize-helper \
	"

do_install:append() {
	# Replace rezie-helper
  	install -m 0755 ${UNPACKDIR}/resize-helper ${D}${sbindir}
}
