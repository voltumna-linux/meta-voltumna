SYSTEMD_SERVICE:${PN} = ""

PACKAGECONFIG:append = "nfsv4"

do_install:append() {
	rm ${D}${systemd_unitdir}/system/sysinit.target.wants/proc-fs-nfsd.mount
}


