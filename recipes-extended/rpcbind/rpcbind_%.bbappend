FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
       file://rpcbind.service \
       "

FILES:${PN}:append = " ${nonarch_libdir}/tmpfiles.d"

do_install:append() {
        install -d ${D}${nonarch_libdir}/tmpfiles.d
        echo 'f /var/run/rpcbind.lock 0644 root root - -' > ${D}${nonarch_libdir}/tmpfiles.d/${BPN}.conf

       # Replace rpcbind.service 
        install -m 0644 ${WORKDIR}/rpcbind.service \
                ${D}${systemd_unitdir}/system
}
