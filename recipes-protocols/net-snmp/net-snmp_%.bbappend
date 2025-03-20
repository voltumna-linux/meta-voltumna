DEPENDS:class-nativesdk = "openssl libnl"

PERLPROG:class-nativesdk = "${USRBINPATH}/env perl"

RDEPENDS:${PN}-libs = " ${PN}-lib-netsnmp \
                        ${PN}-lib-agent \
                        ${PN}-lib-helpers \
                        ${PN}-lib-mibs \
"
BBCLASSEXTEND = "nativesdk"

SYSTEMD_AUTO_ENABLE:${PN}-server-snmpd = "disable"
SYSTEMD_AUTO_ENABLE:${PN}-server-snmptrapd =  "disable"

SRC_URI:remove = "file://0001-unload_all_mibs-fix-memory-leak-by-freeing-tclist.patch"
