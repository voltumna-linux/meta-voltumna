FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

require u-boot-script.inc

SRC_URI_append += " \
	file://uEnv.txt \
	file://boot.scr \
	file://replace_extra_env.patch \
	file://no-usb-eth.cfg \
	"

SRC_URI_append_beagleboneai += " \
	file://disable_bootargs.cfg \
	"

UBOOT_SCRIPT = "boot"

do_deploy_append() {
	install -d ${DEPLOY_DIR_IMAGE}

	install -m 0644 ${WORKDIR}/uEnv.txt ${DEPLOY_DIR_IMAGE}
	sed -i -e "s,@IMAGE_NAME@,default,g" -e "s,@USR@,mount.usr=/.osdir/\$image,g" \
		${DEPLOY_DIR_IMAGE}/uEnv.txt
}

inherit deploy
