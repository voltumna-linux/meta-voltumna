DESCRIPTION = "OS Installer"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

RDEPENDS:${PN} = "bash bmap-tools parted util-linux"

SRC_URI = " \
	file://os-install \
	"

FILES:${PN} = "${base_sbindir}/os-install"

ALLOW_EMPTY:${PN}-dev = "1"

do_install() {
	install -d ${D}${base_sbindir}
	install -m 0755 ${WORKDIR}/os-install ${D}${base_sbindir}
}

inherit allarch
