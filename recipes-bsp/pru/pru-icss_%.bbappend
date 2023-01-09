RDEPENDS:${PN}:remove = " \
    ${PN}-halt \
    ${PN}-rpmsg-echo \
"

do_install:append() {
    install -d ${D}${libdir}
    install -m 0644 ${S}/lib/src/rpmsg_lib/gen/rpmsg_lib.lib ${D}${libdir}
}
