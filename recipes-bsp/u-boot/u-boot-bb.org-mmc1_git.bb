require recipes-bsp/u-boot/u-boot-ti.inc

SUMMARY = "BeagleBoard.org U-Boot"

COMPATIBLE_MACHINE = "beagle.*"

LIC_FILES_CHKSUM = "file://Licenses/README;md5=5a7450c57ffe5ae63fd732446b988025"

PV = "2021.01"

UBOOT_GIT_URI = "git://github.com/beagleboard/u-boot.git"
UBOOT_GIT_PROTOCOL = "https"
BRANCH = "v2021.01-ti-08.05.00.005-SDK-8.5"
SRCREV = "46ff4982b41067e5c93369bddd49b1541856d80b"

BRANCH:beaglebone-ai64 = "v2021.01-ti-08.05.00.001"
BRANCH:beaglebone-ai64-k3r5 = "v2021.01-ti-08.05.00.001"
SRCREV:beaglebone-ai64 = "ea96725b5156135d5875415f75d2188f6f56622a"
SRCREV:beaglebone-ai64-k3r5 = "ea96725b5156135d5875415f75d2188f6f56622a"

BRANCH:beagleplay = "v2021.01-ti-BeaglePlay-Release"
BRANCH:beagleplay-k3r5 = "v2021.01-ti-BeaglePlay-Release"
SRCREV:beagleplay = "f036fbdc25941d7585182d2552c767edb9b04114"
SRCREV:beagleplay-k3r5 = "f036fbdc25941d7585182d2552c767edb9b04114"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

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
