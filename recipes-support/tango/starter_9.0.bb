DESCRIPTION = "Tango Starter"
HOMEPAGE = "http://www.tango-controls.org"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=1ebbd3e34237af26da5dc08a4e440464"

DEPENDS += "cpptango"

SRCREV = "e49cdf0df5a45726fff458717a34f6cb380f1b60"
SRC_URI = "\
	gitsm://gitlab.com/tango-controls/${BPN}.git;protocol=https;branch=main \
	file://01-log-file-home-no-ds.log.patch \
	file://02-starter-stdout.patch \
	file://starter.service \
	"

S = "${WORKDIR}/git"

FILES:${PN} += "${bindir}"

SYSTEMD_SERVICE:${PN} = "starter.service"

do_install:append() {
	install -d ${D}${systemd_unitdir}/system
	install -m 0644 ${WORKDIR}/starter.service ${D}${systemd_unitdir}/system
}

inherit pkgconfig systemd cmake
