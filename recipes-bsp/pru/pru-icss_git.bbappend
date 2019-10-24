RDEPENDS_${PN}_remove = " \
    ${PN}-halt \
    ${PN}-rpmsg-echo \
"

COMPATIBLE_MACHINE_append = "|qemu-cortexa8t2hf-neon"
