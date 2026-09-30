FILESEXTRAPATHS_prepend := "${THISDIR}/${PN}:"

PACKAGE_ARCH = "${MACHINE_ARCH}"

SRC_URI_append = " file://snmpd.local.conf"

DEPENDS_class-nativesdk = "openssl libnl"
PERLPROG_class-nativesdk = "${USRBINPATH}/env perl"

RDEPENDS_${PN}-libs = " ${PN}-lib-netsnmp \
                        ${PN}-lib-agent \
                        ${PN}-lib-helpers \
                        ${PN}-lib-mibs \
"
SYSTEMD_AUTO_ENABLE_${PN}-server-snmpd = "enable"
SYSTEMD_AUTO_ENABLE_${PN}-server-snmptrapd =  "disable"

FILES:${PN} += "${sysconfdir}/snmp"

do_install[vardeps] += "PRIMARY_NETIF"
do_install:append() {
    install -d ${D}${sysconfdir}/snmp
    install -m 644 ${WORKDIR}/snmpd.local.conf ${D}${sysconfdir}/snmp/
    sed -i "s,@ETH@,${@d.getVar('PRIMARY_NETIF') or 'eth0'},g" \
        ${D}${sysconfdir}/snmp/snmpd.local.conf
}

BBCLASSEXTEND = "nativesdk"
