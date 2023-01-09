FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://60voltumna \
	"

FILES:${PN} += "${sysconfdir}/udhcpc.d/60voltumna"

do_install:append() {
	install -d ${D}${sysconfdir}/udhcpc.d/
	install -m 0755 ${WORKDIR}/60voltumna ${D}${sysconfdir}/udhcpc.d/
}
