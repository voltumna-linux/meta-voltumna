DESCRIPTION = "Tango Starter"
HOMEPAGE = "http://www.tango-controls.org"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=1ebbd3e34237af26da5dc08a4e440464"

DEPENDS += "cpptango"

SRCREV = "2c40d9086e4b95e2fea14d0e519667aaa77b68de"
SRC_URI = "\
	gitsm://gitlab.com/tango-controls/${BPN}.git;protocol=https;branch=main \
	file://01-log-file-home-no-ds.log.patch \
	file://02-starter-stdout.patch \
	file://starter.service \
	"

FILES:${PN} += "${bindir}"

SYSTEMD_SERVICE:${PN} = "starter.service"

do_install:append() {
	install -d ${D}${systemd_unitdir}/system
	install -m 0644 ${UNPACKDIR}/starter.service ${D}${systemd_unitdir}/system
}

inherit pkgconfig systemd cmake
