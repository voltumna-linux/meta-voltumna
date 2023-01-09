FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

require recipes-bsp/u-boot/u-boot-ti.inc

LIC_FILES_CHKSUM = "file://Licenses/README;md5=5a7450c57ffe5ae63fd732446b988025"

PR = "r32"

BRANCH = "ti-u-boot-2021.01"

SRCREV = "a169f4261024397dd3ddb944decc1601a623df2a"

PROVIDES = "${BPN}"
PKG:${PN} = "${BPN}"
PKG:${PN}-dev = "${BPN}-dev"
PKG:${PN}-dbg = "${BPN}-dbg"
RDEPENDS:${PN}:remove = " ${PN}-env"

#UBOOT_IMAGE = "u-boot-mmc1-${MACHINE}-${PV}-${PR}.${UBOOT_SUFFIX}"
#UBOOT_SYMLINK = "u-boot-mmc1-${MACHINE}.${UBOOT_SUFFIX}"

#SPL_BINARYNAME = "${@os.path.basename(d.getVar("SPL_BINARY"))}-mmc1"

#SPL_UART_BINARY = ""

SRC_URI:append = " \
	file://use_mmcdev1_for_env.cfg \
	file://u-boot-install \
	file://replace_extra_env_mmc1.patch \
	file://no-usb-eth.cfg \
	"

SRC_URI:append:beagleboneai = " \
	file://disable_bootargs.cfg \
	"

do_install:append () {
	install -d ${D}${datadir}/${BPN}
	install -m 0755 ${WORKDIR}/u-boot-install ${D}${datadir}/${BPN}
	cp ${D}/boot/MLO ${D}/boot/u-boot.img ${D}${datadir}/${BPN}
	rm -fr ${D}${sysconfdir} ${D}/boot
}

deltask do_deploy
