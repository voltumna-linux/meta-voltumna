FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

require u-boot-script.inc

DEPENDS += "${BPN}-mmc1"

SRC_URI_append += " \
	file://uEnv.txt \
	file://boot.scr \
	file://bootcmd.cfg \
	file://replace_extra_env.patch \
	file://no-usb-eth.cfg \
	"

UBOOT_SCRIPT = "boot"

do_deploy_append() {
	install -d ${DEPLOY_DIR_IMAGE}

	_PREFIX=$(echo ${SDK_NAME_PREFIX} | cut -d"-" -f1)
	
	rm -f ${DEPLOY_DIR_IMAGE}/${_PREFIX}-sre-${MACHINE}-*.uEnv.txt
	install -m 0644 ${WORKDIR}/uEnv.txt ${DEPLOY_DIR_IMAGE}/${_PREFIX}-sre-${MACHINE}-${DISTRO_VERSION}.uEnv.txt
	sed -i -e "s,@IMAGE_NAME@,default,g" -e "s,@USR@,mount.usr=/.osdir/\$image,g" \
		-e "s,@USRFLAGS@ ,,g" \
		${DEPLOY_DIR_IMAGE}/${_PREFIX}-sre-${MACHINE}-${DISTRO_VERSION}.uEnv.txt
	
	rm -f ${DEPLOY_DIR_IMAGE}/${_PREFIX}-sde-${MACHINE}-*.uEnv.txt
	install -m 0644 ${WORKDIR}/uEnv.txt ${DEPLOY_DIR_IMAGE}/${_PREFIX}-sde-${MACHINE}-${DISTRO_VERSION}.uEnv.txt
	sed -i -e "s,@IMAGE_NAME@,default,g" -e "s,@USR@,mount.usr=/.osdir/\$image,g" \
		-e "s,@USRFLAGS@,mount.usrflags=rw,g" \
		${DEPLOY_DIR_IMAGE}/${_PREFIX}-sde-${MACHINE}-${DISTRO_VERSION}.uEnv.txt
}

inherit deploy
