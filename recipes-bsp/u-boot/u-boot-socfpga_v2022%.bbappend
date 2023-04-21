FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

require u-boot-script.inc

SRC_URI:append = " \
	file://0001-added-support-for-dinet-board.patch \
	file://0002-preliminary-support-for-Elettra-DAQ-board.patch \
	file://0003-updated-device-tree-for-daq-board.patch \
	file://0004-modified-.its-files-for-DAQ-board.patch \
	file://0005-modified-skew-values-for-dinet-eth.patch \
	file://0006-modified-address-for-adt7470.patch \
	file://0007-enabled-second-i2c-routed-through-FPGA.patch \
	file://0008-corrected-i2c-address-of-fan-controller.patch \
	file://0009-removed-second-i2c-boot-issue.patch \
	file://0010-enabled-spi0-routing-through-fpga.patch \
	file://${UBOOT_SCRIPT_SOURCE} \
	file://uEnv.txt \
	file://replace_extra_env.patch \
	"

SRC_URI:append:arria10 = " \
	file://fit_spl_fpga.itb \
	"

UBOOT_SCRIPT = "boot"

do_install:append() {
	sed -i -e "s,@IMAGE_NAME@,default,g" \
		-e "s,@USR@,mount.usr=/.osdir/\$image,g" \
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
