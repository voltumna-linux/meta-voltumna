SUMMARY = "Python3 port of the Net-SNMP bindings"
HOMEPAGE = "https://github.com/bluecmd/python3-netsnmp/"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://setup.py;md5=cc8e92fedc6a283b7b0d3d476a807e91"

SRC_URI[sha256sum] = "317dd425036a6af87fea4f242ceea73312a385552588629f009662162aa5535f"

inherit pypi setuptools3

PYPI_PACKAGE = "python3-netsnmp"

DEPENDS += "\
    net-snmp \
    "

RDEPENDS:${PN} += "\
    net-snmp-lib-netsnmp \
    "

BBCLASSEXTEND = "nativesdk"
