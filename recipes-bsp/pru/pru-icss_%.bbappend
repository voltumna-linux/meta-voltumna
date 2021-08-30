RDEPENDS_${PN}_remove = " \
    ${PN}-halt \
    ${PN}-rpmsg-echo \
"

do_install_append() {
    install -d ${D}${libdir}
    install -m 0644 ${S}/lib/src/rpmsg_lib/gen/rpmsg_lib.lib ${D}${libdir}
}

# COMPATIBLE_MACHINE_append = "|qemu-cortexa8t2hf-neon"
