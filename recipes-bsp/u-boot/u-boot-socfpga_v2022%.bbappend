FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

require u-boot-script.inc

UBOOT_VERSION_PREFIX = "elettra_"
UBOOT_REPO = "git://gitlab.elettra.eu/intel_socfpga/u-boot-socfpga.git"
SRCREV = "73391decf970359ef124818d9e6186c78150dafa"

SRC_URI:append = " \
	file://${UBOOT_SCRIPT_SOURCE} \
	file://uEnv.txt \
	file://replace_extra_env.patch \
	"

SRC_URI:append:arria10 = " \
	file://fit_spl_fpga.itb \
	"

UBOOT_SCRIPT = "boot"

do_install:append() {
	sed -i -e "s,@USR@,mount.usr=/.osdir/\$image,g" \
		${WORKDIR}/uEnv.txt
}

do_deploy:append() {
	install -m 0644 ${WORKDIR}/uEnv.txt ${DEPLOYDIR}
}

do_deploy:append:arria10() {
	install -m 0644 ${WORKDIR}/fit_spl_fpga.itb ${DEPLOYDIR}
}

addtask deploy after do_install before do_build

inherit deploy
