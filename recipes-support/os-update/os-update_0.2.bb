DESCRIPTION = "OS Updater"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

RDEPENDS_${PN} = "bash curl ca-certificates nginx diffutils rsync python3 python3-requests python3-dbus pam-plugin-succeed-if"

SRC_URI = " \
	file://firmware \
	file://firmware.sh \
	file://firmware.service \
	file://firmware.conf \
	file://os-upgrade \
	file://os-select \
	file://os-netconfig \
	"

SYSTEMD_SERVICE_${PN} = "firmware.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install[vardeps] += "PRIMARY_NETIF"
do_install() {
	install -d ${D}${base_sbindir}
	install -m 0755 ${WORKDIR}/firmware ${WORKDIR}/firmware.sh \
		${WORKDIR}/os-upgrade ${WORKDIR}/os-select \
		${WORKDIR}/os-netconfig \
		${D}${base_sbindir}

	sed -i "s,@ETH@,${@d.getVar('PRIMARY_NETIF')},g" \
		${D}${base_sbindir}/os-netconfig

	install -d ${D}${systemd_unitdir}/system
	install -m 0644 ${WORKDIR}/firmware.service \
		${D}${systemd_unitdir}/system
	
	install -d ${D}${sysconfdir}/nginx/location-conf.d
	install -m 00644 ${WORKDIR}/firmware.conf \
		${D}${sysconfdir}/nginx/location-conf.d
}

inherit allarch systemd
