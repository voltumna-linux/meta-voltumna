DEPENDS += "u-boot-mkimage-native"

UBOOT_SCRIPT_SUFFIX ?= "scr"
UBOOT_SCRIPT_SOURCE ?= "${UBOOT_SCRIPT}.${UBOOT_SCRIPT_SUFFIX}"
UBOOT_SCRIPT_BINARY ?= "${UBOOT_SCRIPT_SOURCE}.uimg"
UBOOT_SCRIPT_IMAGE ?= "${UBOOT_SCRIPT}-${MACHINE}-${PV}-${PR}.${UBOOT_SCRIPT_SUFFIX}.uimg"
UBOOT_SCRIPT_SYMLINK ?= "${UBOOT_SCRIPT}-${MACHINE}.${UBOOT_SCRIPT_SUFFIX}.uimg"

do_compile[vardeps] += "PRIMARY_NETIF"
do_compile_append() {
	if [ "x${UBOOT_SCRIPT}" != "x" ]; then
		cp ${WORKDIR}/${UBOOT_SCRIPT_SOURCE} ${WORKDIR}/${UBOOT_SCRIPT_SOURCE}.filled
		sed -i -e "s,@ROOT@,${ROOT},g" -e "s,@ROOTUSB@,${ROOTUSB},g" \
			-e "s,@ETH@,${@d.getVar('PRIMARY_NETIF')},g" \
			${WORKDIR}/${UBOOT_SCRIPT_SOURCE}.filled

		mkimage -T script -C none -d ${WORKDIR}/${UBOOT_SCRIPT_SOURCE}.filled \
			${WORKDIR}/${UBOOT_SCRIPT_BINARY}
	fi
}

#do_install_append() {
#	if [ "x${UBOOT_SCRIPT}" != "x" ]; then
#		install -d ${D}/boot
#		install -m 644 ${WORKDIR}/${UBOOT_SCRIPT_BINARY} ${D}/boot/${UBOOT_SCRIPT_IMAGE}
#		ln -sfrn ${D}/boot/${UBOOT_SCRIPT_IMAGE} ${D}/boot/${UBOOT_SCRIPT_BINARY}
#		ln -sfrn ${D}/boot/${UBOOT_SCRIPT_IMAGE} ${D}/boot/${UBOOT_SCRIPT_BINARY}-${MACHINE}
#	fi
#}

do_deploy_append() {
	if [ "x${UBOOT_SCRIPT}" != "x" ]; then
		install -d ${DEPLOYDIR}
		install -m 644 ${WORKDIR}/${UBOOT_SCRIPT_BINARY} ${DEPLOYDIR}/${UBOOT_SCRIPT_IMAGE}
		ln -sfrn ${DEPLOYDIR}/${UBOOT_SCRIPT_IMAGE} ${DEPLOYDIR}/${UBOOT_SCRIPT_BINARY}
		ln -sfrn ${DEPLOYDIR}/${UBOOT_SCRIPT_IMAGE} ${DEPLOYDIR}/${UBOOT_SCRIPT_SYMLINK}-${MACHINE}
	fi
}
