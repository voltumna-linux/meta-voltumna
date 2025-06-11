FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = "file://80-diskless.network \
		file://80-standalone.network \
		"

FILES:${PN} += "${systemd_unitdir}"

do_install[vardeps] += "PRIMARY_NETIF"
do_install:append() {
	rm -f ${D}${systemd_unitdir}/network/80-wired.network

	install -d ${D}${systemd_unitdir}/network
	install -D -m 0644 ${UNPACKDIR}/80-standalone.network \
		${UNPACKDIR}/80-diskless.network ${D}${systemd_unitdir}/network/

	sed -i "s,@ETH@,${@d.getVar('PRIMARY_NETIF')},g" \
		${D}${systemd_unitdir}/network/80-diskless.network
	
	sed -i "s,@ETH@,${@d.getVar('PRIMARY_NETIF')},g" \
		${D}${systemd_unitdir}/network/80-standalone.network

	# Remove the defaults
	rm -f ${D}${systemd_unitdir}/*/00-systemd-conf.conf
}
