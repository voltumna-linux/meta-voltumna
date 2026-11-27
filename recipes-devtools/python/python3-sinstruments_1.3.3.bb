SUMMARY = "Sintruments"
HOMEPAGE = "https://github.com/tiagocoutinho/sinstruments"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=1ebbd3e34237af26da5dc08a4e440464"

SRC_URI = " \
	git://github.com/abogani/sinstruments;branch=master;protocol=https \
	"
SRCREV = "2662f9f60babbed581d149554da030f25508b838"

# Tags are vMAJOR.MINOR.PATCH. The check runs against the fork fetched by
# SRC_URI, which is expected to carry the same tags as the upstream
# tiagocoutinho/sinstruments repository. The trailing ^{} also matches the
# peeled entry of annotated tags so that devtool picks their commit as the new
# SRCREV.
UPSTREAM_CHECK_GITTAGREGEX = "^v(?P<pver>\d+(\.\d+)+)(\^\{\})?$"

DEPENDS += "${PYTHON_PN}-pytest-runner-native"
RDEPENDS:${PN} += "\
	${PYTHON_PN}-gevent \
	${PYTHON_PN}-pyyaml \
	${PYTHON_PN}-click \
	${PYTHON_PN}-scpi-protocol \
	"

inherit python3native setuptools3_legacy

BBCLASSEXTEND = "native nativesdk"
