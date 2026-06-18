FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://fix-sigsys.patch \
    file://override.conf \
    "

FILES:${PN}:append = " \
    ${sysconfdir}/systemd/system \
    "

do_install:append() {
	# Remove stuff about old volatile approach
	rm ${D}${sysconfdir}/default/volatiles/99_sshd
	rmdir --ignore-fail-on-non-empty -p ${D}${sysconfdir}/default/volatiles/

	# Enable pam_limits during ssh login
	echo "session    required     pam_limits.so" >> ${D}/etc/pam.d/sshd

        # Add override for sshd@.service and for sshd.socket
        install -d ${D}${sysconfdir}/systemd/system/sshd@.service.d/ \
            ${D}${sysconfdir}/systemd/system/sshd.socket.d/
        install -m 0644 ${WORKDIR}/override.conf \
            ${D}${sysconfdir}/systemd/system/sshd@.service.d/
        install -m 0644 ${WORKDIR}/override.conf \
            ${D}${sysconfdir}/systemd/system/sshd.socket.d/
}
