FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

require u-boot-script.inc

SRC_URI_append += " \
	file://${UBOOT_SCRIPT_SOURCE} \
	file://uEnv.txt \
	file://replace_extra_env.patch \
	file://no-usb-eth.cfg \
	"

SRC_URI_append_beagleboneai += " \
	file://disable_bootargs.cfg \
	"

UBOOT_SCRIPT = "boot"

do_deploy_prepend() {
	touch ${DEPLOYDIR}/u-boot-initial-env
	touch ${DEPLOYDIR}/${PN}-initial-env
	touch ${DEPLOYDIR}/u-boot-initial-env-${MACHINE}
	touch ${DEPLOYDIR}/${PN}-initial-env-${MACHINE}
	touch ${DEPLOYDIR}/u-boot-initial-env-${MACHINE}-${PV}-${PR}
	touch ${DEPLOYDIR}/${PN}-initial-env-${MACHINE}-${PV}-${PR}
}

do_deploy_append() {
	sed -i -e "s,@IMAGE_NAME@,default,g" \
		-e "s,@USR@,mount.usr=/.osdir/\$image,g" \
		${WORKDIR}/uEnv.txt
	install -d ${DEPLOY_DIR_IMAGE}
	install -m 0644 ${WORKDIR}/uEnv.txt ${DEPLOY_DIR_IMAGE}
}
