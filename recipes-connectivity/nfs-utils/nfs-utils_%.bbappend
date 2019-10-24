SYSTEMD_SERVICE_${PN} = ""

do_install_append() {
	rm ${D}${systemd_unitdir}/system/sysinit.target.wants/proc-fs-nfsd.mount
}
