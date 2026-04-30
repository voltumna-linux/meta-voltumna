SUMMARY = "Extensions to the Python standard library unit testing framework"
HOMEPAGE = "https://pypi.org/project/testtools/"
SECTION = "devel/python"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=d6fd7d57d2bdc8678de824fb404cb1a4"

DEPENDS += "python3-hatch-vcs-native"

inherit pypi python_hatchling

SRC_URI[sha256sum] = "eb562d1a2157c6d443c8c118861eb452b3655d1842f9b61b8567ad01b32826e3"

RDEPENDS:${PN} += "\
    python3-compression \
    python3-doctest \
    python3-extras \
    python3-json \
    python3-six \
    "

BBCLASSEXTEND = "nativesdk"

