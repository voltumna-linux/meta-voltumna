do_install:append() {
	# Remove stuff about old volatile approach
	rm ${D}${sysconfdir}/default/volatiles/99_wpa_supplicant
	rmdir --ignore-fail-on-non-empty -p ${D}${sysconfdir}/default/volatiles/
}
