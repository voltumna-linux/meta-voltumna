do_install:append() {
	# Remove stuff about old volatile approach
	rm ${D}${sysconfdir}/default/volatiles/99_sshd
	rmdir --ignore-fail-on-non-empty -p ${D}${sysconfdir}/default/volatiles/

	# Enable pam_limits during ssh login
	echo "session    required     pam_limits.so" >> ${D}/etc/pam.d/sshd
}
