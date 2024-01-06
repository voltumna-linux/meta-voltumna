do_install:append() {
	sed -i '/inet6/d' ${D}${sysconfdir}/netconfig
}
