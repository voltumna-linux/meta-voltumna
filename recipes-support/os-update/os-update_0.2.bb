DESCRIPTION = "OS Updater"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

RDEPENDS:${PN} = "bash curl ca-certificates nginx diffutils rsync python3 python3-requests python3-dbus pam-plugin-succeed-if"

SRC_URI = " \
	file://firmware \
	file://firmware.sh \
	file://firmware.service \
	file://firmware.conf \
	file://os-upgrade \
	file://os-select \
	file://os-netconfig \
	"

SYSTEMD_SERVICE:${PN} = "firmware.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install[vardeps] += "PRIMARY_NETIF"
do_install() {
	install -d ${D}${base_sbindir}
	install -m 0755 ${UNPACKDIR}/firmware ${UNPACKDIR}/firmware.sh \
		${UNPACKDIR}/os-upgrade ${UNPACKDIR}/os-select \
		${UNPACKDIR}/os-netconfig \
		${D}${base_sbindir}

	sed -i "s,@ETH@,${@d.getVar('PRIMARY_NETIF')},g" \
		${D}${base_sbindir}/os-netconfig

	install -d ${D}${systemd_unitdir}/system
	install -m 0644 ${UNPACKDIR}/firmware.service \
		${D}${systemd_unitdir}/system
	
	install -d ${D}${sysconfdir}/nginx/location-conf.d
	install -m 00644 ${UNPACKDIR}/firmware.conf \
		${D}${sysconfdir}/nginx/location-conf.d
}

inherit allarch systemd
