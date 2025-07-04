SUMMARY = "Sintruments"
HOMEPAGE = "https://github.com/tiagocoutinho/sinstruments"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=1ebbd3e34237af26da5dc08a4e440464"

SRC_URI = " \
	git://github.com/abogani/sinstruments;branch=master;protocol=https \
	"
SRCREV = "2662f9f60babbed581d149554da030f25508b838"

DEPENDS += "${PYTHON_PN}-pytest-runner-native"
RDEPENDS:${PN} += "\
	${PYTHON_PN}-gevent \
	${PYTHON_PN}-pyyaml \
	${PYTHON_PN}-click \
	${PYTHON_PN}-scpi-protocol \
	"

inherit python3native setuptools3_legacy

BBCLASSEXTEND = "native nativesdk"
