FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

require ${COREBASE}/meta/recipes-bsp/u-boot/u-boot.inc
require u-boot-script.inc

inherit deploy

SUMMARY = "Dummy u-boot bootloader"
LICENSE = "GPLv2"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/GPL-2.0;md5=801f80980d171dd6425610833a22dbe6"

UBOOT_MACHINE="dummy"
PROVIDES += "virtual/bootloader"

SRC_URI = " \
	file://${UBOOT_SCRIPT_SOURCE} \
	file://uEnv.txt \
	"

UBOOT_SCRIPT = "boot"

COMPATIBLE_HOST = ".*-linux"

PR = "r1"

S = "${WORKDIR}"

INHIBIT_DEFAULT_DEPS = "1"
ALLOW_EMPTY_${PN} = "1"

do_configure() {
	:
}

do_compile() {
	:
}

do_install() {
	:
}

do_deploy() {
	sed -i -e "s,@IMAGE_NAME@,default,g" \
		-e "s,@USR@,mount.usr=/.osdir/\$image,g" \
		${WORKDIR}/uEnv.txt
	install -d ${DEPLOY_DIR_IMAGE}
	install -m 0644 ${WORKDIR}/uEnv.txt ${DEPLOY_DIR_IMAGE}
}

addtask deploy after do_install
