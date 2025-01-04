FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

require u-boot-script.inc

SRC_URI:append = " \
	file://${UBOOT_SCRIPT_SOURCE} \
	file://uEnv.txt \
	file://replace_extra_env.patch \
	"

UBOOT_SCRIPT = "boot"

do_install:append() {
	sed -i -e "s,@USR@,mount.usr=/.osdir/\$image,g" \
		${WORKDIR}/uEnv.txt
}

do_deploy:append() {
	install -m 0644 ${WORKDIR}/uEnv.txt ${DEPLOYDIR}
}

addtask deploy after do_install before do_build

inherit deploy
