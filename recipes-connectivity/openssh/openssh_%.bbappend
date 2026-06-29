FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append = " \
    file://override.conf \
    "

FILES_${PN}_append = " \
    ${sysconfdir}/systemd/system \
    "

do_install_append() {
	# Remove stuff about old volatile approach
	rm ${D}${sysconfdir}/default/volatiles/99_sshd
	rmdir --ignore-fail-on-non-empty -p ${D}${sysconfdir}/default/volatiles/

	# Enable pam_limits during ssh login
	echo "session    required     pam_limits.so" >> ${D}/etc/pam.d/sshd

        # Add override for sshd@.service
        install -d ${D}${sysconfdir}/systemd/system/sshd@.service.d/
        install -m 0644 ${WORKDIR}/override.conf \
            ${D}${sysconfdir}/systemd/system/sshd@.service.d/
}
