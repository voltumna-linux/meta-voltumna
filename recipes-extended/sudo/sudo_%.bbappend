do_install:append() {
    rm -f ${D}${sysconfdir}/sudoers.dist ${D}${sysconfdir}/sudo_logsrvd.conf
}
