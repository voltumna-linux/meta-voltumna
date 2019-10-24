DESCRIPTION = "OS Updater"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

RDEPENDS_${PN} = "bash curl nginx rsync python3"

SRC_URI = " \
	file://firmware \
	file://firmware.sh \
	file://firmware.service \
	file://firmware.conf \
	file://os-upgrade \
	file://os-select \
	"

SYSTEMD_SERVICE_${PN} = "firmware.service"

do_install() {
	install -d ${D}${base_sbindir}
	install -m 0755 ${WORKDIR}/firmware ${WORKDIR}/firmware.sh \
		${WORKDIR}/os-upgrade ${WORKDIR}/os-select ${D}${base_sbindir}

	install -d ${D}${systemd_unitdir}/system
	install -m 0644 ${WORKDIR}/firmware.service ${D}${systemd_unitdir}/system
	
	install -d ${D}${sysconfdir}/nginx/location-conf.d
	install -m 00644 ${WORKDIR}/firmware.conf ${D}${sysconfdir}/nginx/location-conf.d
}

inherit allarch systemd
