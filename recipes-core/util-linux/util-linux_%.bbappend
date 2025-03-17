FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://fstrim.service \
	file://fstrim.timer \
	"

FILES:${PN} += "${sysconfdir} usr/lib/systemd"

do_install:append() {
	mkdir -p ${D}${sysconfdir}/systemd/system/timers.target.wants/ \
		${D}/usr/lib/systemd/system/ ${D}/usr/lib/systemd/system-preset
	install -m 0644 ${WORKDIR}/fstrim.timer ${WORKDIR}/fstrim.service \
		${D}/usr/lib/systemd/system/
	echo "enable fstrim.timer" > ${D}/usr/lib/systemd/system-preset/98-fstrim.preset
	ln -sr ${D}/usr/lib/systemd/system/fstrim.timer ${D}${sysconfdir}/systemd/system/timers.target.wants/fstrim.timer
}
