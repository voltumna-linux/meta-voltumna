FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://grub.cfg \
	"

do_deploy[vardeps] += "PRIMARY_NETIF"
do_deploy() {
	install -m 0644 ${WORKDIR}/grub.cfg ${DEPLOYDIR}
	sed -i 	-e "s,@ROOT@,${ROOT},g" \
		-e "s,@ETH@,${@d.getVar('PRIMARY_NETIF')},g" \
		${DEPLOYDIR}/grub.cfg
}

addtask deploy after do_install

inherit deploy
