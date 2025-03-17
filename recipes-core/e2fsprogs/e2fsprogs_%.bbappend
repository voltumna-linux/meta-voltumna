do_install_append() {
	for n in 2 3 4; do
		rm -f ${D}${base_sbindir}/fsck.ext${n}
		lnr ${D}${base_sbindir}/e2fsck ${D}${base_sbindir}/fsck.ext${n}
	done
}
