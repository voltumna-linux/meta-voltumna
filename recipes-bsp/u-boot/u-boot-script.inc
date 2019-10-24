DEPENDS += "u-boot-mkimage-native"

UBOOT_SCRIPT_SUFFIX ?= "scr"
UBOOT_SCRIPT_SOURCE ?= "${UBOOT_SCRIPT}.${UBOOT_SCRIPT_SUFFIX}"
UBOOT_SCRIPT_BINARY ?= "${UBOOT_SCRIPT_SOURCE}.uimg"
UBOOT_SCRIPT_IMAGE ?= "${UBOOT_SCRIPT}-${MACHINE}-${PV}-${PR}.${UBOOT_SCRIPT_SUFFIX}.uimg"
UBOOT_SCRIPT_SYMLINK ?= "${UBOOT_SCRIPT}-${MACHINE}.${UBOOT_SCRIPT_SUFFIX}.uimg"

do_compile_append() {
	sed -i -e "s,@ROOT@,${ROOT},g" \
		-e "s,@ROOTUSB@,${ROOTUSB},g" \
		-e "s,@ETH@,${@d.getVar('PRIMARY_NETIF').split(' ')[0]},g" \
		${WORKDIR}/${UBOOT_SCRIPT_SOURCE}

	if [ "x${UBOOT_SCRIPT}" != "x" ]; then
		mkimage -T script -C none -d ${WORKDIR}/${UBOOT_SCRIPT_SOURCE} \
			${WORKDIR}/${UBOOT_SCRIPT_BINARY}
	fi
}

do_install_append() {
	if [ "x${UBOOT_SCRIPT}" != "x" ]; then
	        install -m 644 ${WORKDIR}/${UBOOT_SCRIPT_BINARY} ${D}/boot/${UBOOT_SCRIPT_IMAGE}
        	lnr ${UBOOT_SCRIPT_IMAGE} ${D}/boot/${UBOOT_SCRIPT_BINARY}
	fi
}

do_deploy_append() {
	if [ "x${UBOOT_SCRIPT}" != "x" ]; then
		install -d ${DEPLOYDIR}
		install -m 644 ${WORKDIR}/${UBOOT_SCRIPT_BINARY} ${DEPLOYDIR}/${UBOOT_SCRIPT_IMAGE}
	        rm -f ${DEPLOYDIR}/${UBOOT_SCRIPT_BINARY} ${DEPLOYDIR}/${UBOOT_SCRIPT_SYMLINK}
	        lnr ${UBOOT_SCRIPT_IMAGE} ${DEPLOYDIR}/${UBOOT_SCRIPT_BINARY}
	        lnr ${UBOOT_SCRIPT_IMAGE} ${DEPLOYDIR}/${UBOOT_SCRIPT_SYMLINK}
	fi
}
