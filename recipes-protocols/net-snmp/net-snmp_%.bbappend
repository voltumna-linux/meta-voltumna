FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

PACKAGE_ARCH:class-target = "${MACHINE_ARCH}"

SRC_URI:append = " file://snmpd.local.conf"

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

FILES:${PN} += "${sysconfdir}/snmp"

do_install[vardeps] += "PRIMARY_NETIF"
do_install:append() {
    install -d ${D}${sysconfdir}/snmp
    install -m 644 ${WORKDIR}/snmpd.local.conf ${D}${sysconfdir}/snmp/
    sed -i "s,@ETH@,${@d.getVar('PRIMARY_NETIF') or 'eth0'},g" \
        ${D}${sysconfdir}/snmp/snmpd.local.conf
}

BBCLASSEXTEND:append = " nativesdk"
