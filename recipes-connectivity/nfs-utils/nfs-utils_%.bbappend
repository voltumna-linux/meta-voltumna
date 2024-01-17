FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SYSTEMD_SERVICE:${PN} = ""

PACKAGECONFIG:append = "nfsv4 nfsv41"

SRC_URI:append = " \
       file://nfs-statd.service \
       "

FILES:${PN}-client:append = " ${nonarch_libdir}/tmpfiles.d"


do_install:append() {
	rm ${D}${systemd_unitdir}/system/sysinit.target.wants/proc-fs-nfsd.mount

       install -d ${D}${nonarch_libdir}/tmpfiles.d     
       echo 'd /var/lib/nfs/v4recovery 0755 root root - -' > ${D}${nonarch_libdir}/tmpfiles.d/${BPN}.conf
       echo 'd /var/lib/nfs/statd 0755 rpcuser rpcuser - -' >>${D}${nonarch_libdir}/tmpfiles.d/${BPN}.conf
       echo 'd /var/lib/nfs/statd/sm 0700 rpcuser rpcuser - -' >>${D}${nonarch_libdir}/tmpfiles.d/${BPN}.conf
       echo 'd /var/lib/nfs/statd/sm.bak 0700 rpcuser rpcuser - -' >>${D}${nonarch_libdir}/tmpfiles.d/${BPN}.conf

       # Replace nfs-statd.service 
        install -m 0644 ${WORKDIR}/nfs-statd.service \
                ${D}${systemd_unitdir}/system
}
