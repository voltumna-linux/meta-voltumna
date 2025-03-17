FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

inherit systemd

SYSTEMD_SERVICE:${PN} = "dpkg-configure-pending.service"
SYSTEMD_AUTO_ENABLE = "enable"

SRC_URI += " \
    file://dpkg-configure-pending.service \
    file://dpkg-configure-pending \
"

do_install:append () {
    install -d ${D}${systemd_unitdir}/system
    install -m 644 ${WORKDIR}/dpkg-configure-pending.service ${D}${systemd_unitdir}/system/
    install -m 755 ${WORKDIR}/dpkg-configure-pending ${D}${sbindir}/dpkg-configure-pending
}

FILES:${PN} += " \
    ${systemd_unitdir}/system/dpkg-configure-pending.service \
    ${sbindir}/dpkg-configure-pending \
"
