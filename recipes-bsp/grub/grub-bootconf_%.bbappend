FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI += " \
	file://grub.cfg \
	"

do_deploy() {
	install -d ${DEPLOY_DIR_IMAGE}

#	_PREFIX=$(echo ${SDK_NAME_PREFIX} | cut -d"-" -f1)
	install -m 644 ${WORKDIR}/grub.cfg ${DEPLOY_DIR_IMAGE}
	sed -i 	-e "s,@ROOT@,${ROOT},g" -e "s,@IMAGE_NAME@,default,g" \
		-e "s,@ETH@,${@d.getVar('PRIMARY_NETIF').split(' ')[0]},g" \
		${WORKDIR}/grub.cfg
#	sed -i -e "s,@IMAGE_NAME@,${_PREFIX}-sre-${MACHINE}-${DISTRO_VERSION},g" \
#		${DEPLOY_DIR_IMAGE}/${_PREFIX}-sre-${MACHINE}-${DISTRO_VERSION}.grub.cfg
}
addtask do_deploy after do_install
