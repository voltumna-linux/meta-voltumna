FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

PACKAGE_ARCH:class-target = "${MACHINE_ARCH}"

SRC_URI:append = "  \
    file://snmpd.local.conf \
    file://override.conf \
    "

PACKAGECONFIG:append = " ipv6"

DEPENDS:class-nativesdk = "openssl libnl"
PERLPROG:class-nativesdk = "${USRBINPATH}/env perl"

RDEPENDS:${PN}-libs = " ${PN}-lib-netsnmp \
                        ${PN}-lib-agent \
                        ${PN}-lib-helpers \
                        ${PN}-lib-mibs \
"
# SDK host needs headers/libs/tools only, not daemons.
# Upstream RDEPENDS:${PN}-dev pulls -server which is unbuildable for
# nativesdk (sbindir==bindir, client swallows daemons, snmptrapd pkg empty).
RDEPENDS:${PN}-dev:class-nativesdk = "${PN}-client (= ${EXTENDPKGV})"
RRECOMMENDS:${PN}-dbg:class-nativesdk = "${PN}-client (= ${EXTENDPKGV})"
SYSTEMD_AUTO_ENABLE:${PN}-server-snmpd = "enable"
SYSTEMD_AUTO_ENABLE:${PN}-server-snmptrapd =  "disable"

FILES:${PN} += " \
    ${sysconfdir}/snmp \
    ${sysconfdir}/systemd \
"

do_install[vardeps] += "PRIMARY_NETIF"
do_install:append() {
    install -d ${D}${sysconfdir}/snmp
    install -m 644 ${UNPACKDIR}/snmpd.local.conf ${D}${sysconfdir}/snmp/
    sed -i -e "s,@DISTRO_NAME@,${@d.getVar('DISTRO_NAME')},g" \
        -e "s,@DISTRO_VERSION@,${@d.getVar('DISTRO_VERSION')},g" \
        -e "s,@MACHINE@,${@d.getVar('MACHINE')},g" \
        ${D}${sysconfdir}/snmp/snmpd.local.conf

    install -d ${D}${sysconfdir}/systemd/system/snmpd.service.d/
    install -m 644 ${UNPACKDIR}/override.conf \
        ${D}${sysconfdir}/systemd/system/snmpd.service.d/
    sed -i "s,@ETH@,${@d.getVar('PRIMARY_NETIF') or 'eth0'},g" \
        ${D}${sysconfdir}/systemd/system/snmpd.service.d/override.conf
}

BBCLASSEXTEND:append = " nativesdk"
