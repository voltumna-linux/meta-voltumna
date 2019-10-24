FILES_${PN} += "${sysconfdir} usr/lib/systemd"

do_install_append() {
	mkdir -p ${D}${sysconfdir}/systemd/system/timers.target.wants/ \
		${D}/usr/lib/systemd/system/ ${D}/usr/lib/systemd/system-preset
	install -m 0644 ${S}/sys-utils/fstrim.timer ${S}/sys-utils/fstrim.service.in \
		${D}/usr/lib/systemd/system/
	sed -i -e 's,@sbindir@,${sbindir},g' ${D}/usr/lib/systemd/system/fstrim.service.in
	mv ${D}/usr/lib/systemd/system/fstrim.service.in ${D}/usr/lib/systemd/system/fstrim.service
	echo "enable fstrim.timer" > ${D}/usr/lib/systemd/system-preset/98-fstrim.preset
	lnr ${D}/usr/lib/systemd/system/fstrim.timer ${D}${sysconfdir}/systemd/system/timers.target.wants/fstrim.timer
}
