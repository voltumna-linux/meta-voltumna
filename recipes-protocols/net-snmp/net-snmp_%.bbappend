DEPENDS_class-nativesdk = "openssl libnl"

PERLPROG:class-nativesdk = "${USRBINPATH}/env perl"

RDEPENDS_${PN}-libs = " ${PN}-lib-netsnmp \
                        ${PN}-lib-agent \
                        ${PN}-lib-helpers \
                        ${PN}-lib-mibs \
"
BBCLASSEXTEND = "nativesdk"

SYSTEMD_AUTO_ENABLE_${PN}-server-snmpd = "disable"
SYSTEMD_AUTO_ENABLE_${PN}-server-snmptrapd =  "disable"
