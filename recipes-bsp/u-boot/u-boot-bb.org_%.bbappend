FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

require u-boot-script.inc

SRCREV = "a169f4261024397dd3ddb944decc1601a623df2a"

SRC_URI:append = " \
	file://${UBOOT_SCRIPT_SOURCE} \
	file://uEnv.txt \
	file://replace_extra_env.patch \
	file://no-usb-eth.cfg \
	"

SRC_URI:append:beagleboneai = " \
	file://disable_bootargs.cfg \
	"

UBOOT_SCRIPT = "boot"

do_deploy:prepend() {
	touch ${DEPLOYDIR}/u-boot-initial-env
	touch ${DEPLOYDIR}/${PN}-initial-env
	touch ${DEPLOYDIR}/u-boot-initial-env-${MACHINE}
	touch ${DEPLOYDIR}/${PN}-initial-env-${MACHINE}
	touch ${DEPLOYDIR}/u-boot-initial-env-${MACHINE}-${PV}-${PR}
	touch ${DEPLOYDIR}/${PN}-initial-env-${MACHINE}-${PV}-${PR}
}

do_install:append() {
	sed -i -e "s,@USR@,mount.usr=/.osdir/\$image,g" \
		${WORKDIR}/uEnv.txt
}

do_deploy:append() {
	install -m 0644 ${WORKDIR}/uEnv.txt ${DEPLOYDIR}
}
