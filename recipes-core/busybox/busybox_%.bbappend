FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI += " \
	file://add-elettra-specific-dhcp-parameters.patch \
	file://60elettra \
	"

FILES_${PN} += "${sysconfdir}/udhcpc.d/60elettra"

do_install_append() {
	install -d ${D}${sysconfdir}/udhcpc.d/
	install -m 0755 ${WORKDIR}/60elettra ${D}${sysconfdir}/udhcpc.d/
}
