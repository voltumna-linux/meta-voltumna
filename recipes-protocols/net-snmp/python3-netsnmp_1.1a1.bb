SUMMARY = "Python3 port of the Net-SNMP bindings"
HOMEPAGE = "https://github.com/bluecmd/python3-netsnmp/"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://setup.py;md5=cc8e92fedc6a283b7b0d3d476a807e91"

SRC_URI[sha256sum] = "317dd425036a6af87fea4f242ceea73312a385552588629f009662162aa5535f"

inherit pypi setuptools3_legacy

PYPI_PACKAGE = "python3-netsnmp"

# The pypi.bbclass default regex would read 1.1a1 as 1.1 (and then fail to
# match the file at all): include the PEP 440 style suffix in the captured
# version instead.
UPSTREAM_CHECK_REGEX = "${UPSTREAM_CHECK_PYPI_PACKAGE}-(?P<pver>\d+\.\d+[a-z]?\d*)\.tar\.gz"

DEPENDS += "\
    net-snmp \
    "

RDEPENDS:${PN} += "\
    net-snmp-lib-netsnmp \
    "

BBCLASSEXTEND = "nativesdk"
