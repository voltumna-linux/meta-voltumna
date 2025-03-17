SUMMARY = "Tango for Python"
DESCRIPTION = "PyTango is a python module that exposes to Python the complete Tango C++ API"
HOMEPAGE = "https://pytango.readthedocs.io/"

LICENSE = "LGPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE.txt;md5=e6a600fd5e1d9cbde2d983680233ad02"

PYPI_PACKAGE = "pytango"
SRC_URI[sha256sum] = "6af91181cdbe5f729580a8e5cd487fcb47193147b8ef470ced9ecfd2f49257f5"

SRC_URI = " \
    file://force-boost_library_name.patch \
    "

DEPENDS += "\
    boost \
    cpptango \
    ${PYTHON_PN}-numpy-native \
    "

INSANE_SKIP:${PN} += "file-rdeps"

RDEPENDS:${PN} += "\
    ${PYTHON_PN}-numpy \
    ${PYTHON_PN}-six \
    "

inherit pypi pkgconfig setuptools3

BBCLASSEXTEND = "nativesdk"
