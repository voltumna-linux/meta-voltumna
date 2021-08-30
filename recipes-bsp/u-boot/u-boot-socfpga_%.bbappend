FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

require u-boot-script.inc

SRC_URI_append += " \
	file://${UBOOT_SCRIPT_SOURCE} \
	file://uEnv.txt \
	file://replace_extra_env.patch \
	"

UBOOT_SCRIPT = "boot"

do_deploy_append() {
	sed -i -e "s,@IMAGE_NAME@,default,g" \
		-e "s,@USR@,mount.usr=/.osdir/\$image,g" \
		${WORKDIR}/uEnv.txt
	install -d ${DEPLOY_DIR_IMAGE}
	install -m 0644 ${WORKDIR}/uEnv.txt ${DEPLOY_DIR_IMAGE}
}

