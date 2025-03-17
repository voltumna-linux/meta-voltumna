FILESEXTRAPATHS_prepend := "${THISDIR}/libpam:"

do_install_append() {
	# Remove stuff about old volatile approach
	rm ${D}${sysconfdir}/default/volatiles/99_pam
	rmdir --ignore-fail-on-non-empty -p ${D}${sysconfdir}/default/volatiles/
}
