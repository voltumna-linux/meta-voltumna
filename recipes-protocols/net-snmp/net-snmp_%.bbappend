DEPENDS_class-nativesdk = "openssl libnl"

RDEPENDS_${PN}-libs = " ${PN}-lib-netsnmp \
                        ${PN}-lib-agent \
                        ${PN}-lib-helpers \
                        ${PN}-lib-mibs \
"
BBCLASSEXTEND = "nativesdk"
