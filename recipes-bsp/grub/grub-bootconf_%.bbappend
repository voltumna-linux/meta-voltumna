FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI += " \
	file://grub.cfg \
	"

do_install_prepend() {
	install -d ${DEPLOY_DIR_IMAGE}

	install -m 644 ${WORKDIR}/grub.cfg ${DEPLOY_DIR_IMAGE}
	sed -i 	-e "s,@ROOT@,${ROOT},g" -e "s,@IMAGE_NAME@,default,g" \
		-e "s,@ETH@,${@d.getVar('PRIMARY_NETIF').split(' ')[0]},g" \
		${WORKDIR}/grub.cfg
}
