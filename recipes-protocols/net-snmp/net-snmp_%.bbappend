FILESEXTRAPATHS_prepend := "${THISDIR}/${PN}:"

PACKAGE_ARCH = "${MACHINE_ARCH}"

SRC_URI_append = "  \
    file://snmpd.local.conf \
    file://override.conf \
    "

DEPENDS_class-nativesdk = "openssl libnl"
PERLPROG_class-nativesdk = "${USRBINPATH}/env perl"

RDEPENDS_${PN}-libs = " ${PN}-lib-netsnmp \
                        ${PN}-lib-agent \
                        ${PN}-lib-helpers \
                        ${PN}-lib-mibs \
"
SYSTEMD_AUTO_ENABLE_${PN}-server-snmpd = "enable"
SYSTEMD_AUTO_ENABLE_${PN}-server-snmptrapd =  "disable"

FILES_${PN} += " \
    ${sysconfdir}/snmp \
    ${sysconfdir}/systemd \
"

do_install[vardeps] += "PRIMARY_NETIF"
do_install_append() {
    install -d ${D}${sysconfdir}/snmp
    install -m 644 ${WORKDIR}/snmpd.local.conf ${D}${sysconfdir}/snmp/
    sed -i -e "s,@DISTRO_NAME@,${@d.getVar('DISTRO_NAME')},g" \
        -e "s,@DISTRO_VERSION@,${@d.getVar('DISTRO_VERSION')},g" \
        -e "s,@MACHINE@,${@d.getVar('MACHINE')},g" \
        -e "s,@MAINTAINER@,${@d.getVar('MAINTAINER')},g" \
        ${D}${sysconfdir}/snmp/snmpd.local.conf

    install -d ${D}${sysconfdir}/systemd/system/snmpd.service.d/
    install -m 644 ${WORKDIR}/override.conf \
        ${D}${sysconfdir}/systemd/system/snmpd.service.d/
    sed -i "s,@ETH@,${@d.getVar('PRIMARY_NETIF') or 'eth0'},g" \
        ${D}${sysconfdir}/systemd/system/snmpd.service.d/override.conf

    sed -i -e 's,^\(com2sec[[:space:]]*paranoid[[:space:]]*default[[:space:]]*public\),#\1,' \
        ${D}${sysconfdir}/snmp/snmpd.conf
}

BBCLASSEXTEND = "nativesdk"
