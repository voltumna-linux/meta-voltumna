FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append += "file://80-diskless.network \
		file://80-standalone.network \
		"

FILES_${PN} += "${systemd_unitdir}/network"

do_install_append() {
	rm -f ${D}${systemd_unitdir}/network/80-wired.network

	sed -i "s,@ETH@,${@d.getVar('PRIMARY_NETIF').split(' ')[0]},g" \
		${WORKDIR}/80-diskless.network
	
	sed -i "s,@ETH@,${@d.getVar('PRIMARY_NETIF').split(' ')[1]},g" \
		${WORKDIR}/80-standalone.network

	install -d ${D}${systemd_unitdir}/network	
	install	-D -m 0644 ${WORKDIR}/80-standalone.network \
		${WORKDIR}/80-diskless.network ${D}${systemd_unitdir}/network/

}
