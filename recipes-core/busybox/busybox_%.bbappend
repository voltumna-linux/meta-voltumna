FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI += " \
	file://add-elettra-specific-dhcp-parameters.patch \
	file://60voltumna \
	"

FILES_${PN} += "${sysconfdir}/udhcpc.d/60voltumna"

do_install_append() {
	install -d ${D}${sysconfdir}/udhcpc.d/
	install -m 0755 ${WORKDIR}/60voltumna ${D}${sysconfdir}/udhcpc.d/
}
