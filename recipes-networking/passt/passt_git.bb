SUMMARY = "User-mode networking daemons for virtual machines and namespaces"
LICENSE = "BSD-3-Clause AND GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://LICENSES/GPL-2.0-or-later.txt;md5=3d26203303a722dedc6bf909d95ba815 \
                    file://LICENSES/BSD-3-Clause.txt;md5=c6c623ff088c13278097b9f79637ca77"

DEPENDS += "coreutils-native"

EXTRA_OEMAKE += "\
    'DESTDIR=${D}' \
    'prefix=${prefix}' \
    'bindir=${bindir}' \
    'sharedir=${datadir}' \
    'sysconfdir=${sysconfdir}' \
    "

SRC_URI = "git://passt.top/passt;branch=master"

PV = "2026_07_16+git"
SRCREV = "defc25b9444c508d21badb6bc9a0b835ddd01126"

do_configure () {
	:
}

do_compile () {
	oe_runmake
}

do_install () {
	oe_runmake install
}

