DESCRIPTION = "Tango Database"
HOMEPAGE = "http://www.tango-controls.org"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=1ebbd3e34237af26da5dc08a4e440464"

DEPENDS += "cpptango mariadb"

SRCREV = "8fdebf233943250a0823452f14d3e32815b42d76"
SRC_URI = "\
	gitsm://gitlab.com/tango-controls/${BPN}.git;protocol=https;branch=main \
	"

S = "${WORKDIR}/git"

FILES_${PN} += "${bindir} ${datadir}"

#SYSTEMD_SERVICE_${PN} = "starter.service"
#
#do_install:append() {
#	install -d ${D}${systemd_unitdir}/system
#	install -m 0644 ${WORKDIR}/starter.service ${D}${systemd_unitdir}/system
#}

inherit pkgconfig systemd cmake
