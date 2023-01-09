FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://grub.cfg \
	"

do_install:append() {
	sed -i 	-e "s,@ROOT@,${ROOT},g" -e "s,@IMAGE_NAME@,default,g" \
		-e "s,@ETH@,${@d.getVar('PRIMARY_NETIF')},g" \
		${WORKDIR}/grub.cfg
	
}

do_deploy() {
	install -m 0644 ${WORKDIR}/grub.cfg ${DEPLOYDIR}
}

addtask deploy after do_install before do_build

inherit deploy
