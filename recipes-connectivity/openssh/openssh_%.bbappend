FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI += " \
	file://CVE-2024-6387.patch \
	"

do_install_append() {
	# Remove stuff about old volatile approach
	rm ${D}${sysconfdir}/default/volatiles/99_sshd
	rmdir --ignore-fail-on-non-empty -p ${D}${sysconfdir}/default/volatiles/
}
