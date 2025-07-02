SUMMARY = "Prepare kernel development source"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
	file://prepare-kernel-devsrc.service \
	"

SYSTEMD_SERVICE:${PN} = "prepare-kernel-devsrc.service"

FILES:${PN} += "${systemd_unitdir}/system"

do_install() {
	install -d ${D}${systemd_system_unitdir}
	install -m 0644 ${UNPACKDIR}/prepare-kernel-devsrc.service \
		${D}${systemd_system_unitdir}
}

inherit systemd
