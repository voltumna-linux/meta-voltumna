FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

PACKAGE_ARCH = "${MACHINE_ARCH}"

SRC_URI:append = " file://snmpd.local.conf"

PACKAGECONFIG:append = " ipv6"

DEPENDS:class-nativesdk = "openssl libnl"
PERLPROG:class-nativesdk = "${USRBINPATH}/env perl"

RDEPENDS:${PN}-libs = " ${PN}-lib-netsnmp \
                        ${PN}-lib-agent \
                        ${PN}-lib-helpers \
                        ${PN}-lib-mibs \
"
SYSTEMD_AUTO_ENABLE:${PN}-server-snmpd = "enable"
SYSTEMD_AUTO_ENABLE:${PN}-server-snmptrapd =  "disable"

FILES:${PN} += "${sysconfdir}/snmp"

do_install[vardeps] += "PRIMARY_NETIF"
do_install:append() {
    install -d ${D}${sysconfdir}/snmp
    install -m 644 ${UNPACKDIR}/snmpd.local.conf ${D}${sysconfdir}/snmp/
    sed -i "s,@ETH@,${@d.getVar('PRIMARY_NETIF') or 'eth0'},g" \
        ${D}${sysconfdir}/snmp/snmpd.local.conf
}

BBCLASSEXTEND = "nativesdk"
