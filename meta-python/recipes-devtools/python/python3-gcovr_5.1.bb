DESCRIPTION = "generate GCC code coverage reports"
HOMEPAGE = "https://gcovr.com"
SECTION = "devel/python"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE.txt;md5=08208c66520e8d69d5367483186d94ed"

SRC_URI = "git://github.com/gcovr/gcovr.git;branch=main;protocol=https"
SRC_URI += "file://0001-Fix-parsing-of-gcov-metadata-601.patch"
SRCREV = "e71e883521b78122c49016eb4e510e6da06c6916"

S = "${WORKDIR}/git"

inherit setuptools3
PIP_INSTALL_PACKAGE = "gcovr"

RDEPENDS:${PN} += "${PYTHON_PN}-jinja2 ${PYTHON_PN}-lxml ${PYTHON_PN}-setuptools ${PYTHON_PN}-pygments ${PYTHON_PN}-multiprocessing"

BBCLASSEXTEND = "native nativesdk"
