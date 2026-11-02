do_install_append() {
    rm -f ${D}${sysconfdir}/sudoers.dist ${D}${sysconfdir}/sudo_logsrvd.conf
}
