FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://add-elettra-specific-dhcp-parameters.patch \
	file://60voltumna \
	"

FILES:${PN} += "${sysconfdir}/udhcpc.d/60voltumna"

do_install:append() {
	install -d ${D}${sysconfdir}/udhcpc.d/
	install -m 0755 ${UNPACKDIR}/60voltumna ${D}${sysconfdir}/udhcpc.d/
}
