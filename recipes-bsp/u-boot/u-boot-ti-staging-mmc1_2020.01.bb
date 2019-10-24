FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

require u-boot-ti.inc

PR = "r18"

BRANCH = "ti-u-boot-2020.01"

SRCREV = "eea73800730b3d9125f5c12a629db2f88e566b71"

PROVIDES = "${BPN}"
PKG_${PN} = "${BPN}"
PKG_${PN}-dev = "${BPN}-dev"
PKG_${PN}-dbg = "${BPN}-dbg"

UBOOT_IMAGE = "u-boot-mmc1-${MACHINE}-${PV}-${PR}.${UBOOT_SUFFIX}"
UBOOT_SYMLINK = "u-boot-mmc1-${MACHINE}.${UBOOT_SUFFIX}"

SPL_BINARYNAME = "${@os.path.basename(d.getVar("SPL_BINARY"))}-mmc1"

SPL_UART_BINARY = ""

SRC_URI_append += " \
	file://use_mmcdev1_for_env.cfg \
	file://u-boot-install \
	file://bootcmd.cfg \
	file://replace_extra_env_mmc1.patch \
	file://no-usb-eth.cfg \
	"

RDEPENDS_${PN}_remove = " ${PN}-env"

do_install_append () {
	install -d ${D}${datadir}/${BPN}
	install -m 0755 ${WORKDIR}/u-boot-install ${D}${datadir}/${BPN}
	mv ${D}/boot/MLO-mmc1-* ${D}/boot/u-boot* ${D}${datadir}/${BPN}
	mv ${D}/boot/MLO-mmc1 ${D}${datadir}/${BPN}/MLO
	rm -fr ${D}${sysconfdir} ${D}/boot
}
