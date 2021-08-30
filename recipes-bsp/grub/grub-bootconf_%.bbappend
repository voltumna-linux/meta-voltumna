FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI += " \
	file://grub.cfg \
	"

do_install_append() {
	sed -i 	-e "s,@ROOT@,${ROOT},g" -e "s,@IMAGE_NAME@,default,g" \
		-e "s,@ETH@,${@d.getVar('PRIMARY_NETIF')},g" \
		${WORKDIR}/grub.cfg
	
	install -d ${DEPLOY_DIR_IMAGE}
	install -m 0644 ${WORKDIR}/grub.cfg ${DEPLOY_DIR_IMAGE}
}
