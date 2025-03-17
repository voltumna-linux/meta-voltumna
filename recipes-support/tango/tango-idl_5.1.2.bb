DESCRIPTION = "Tango CORBA IDL file"
HOMEPAGE = "http://www.tango-controls.org"
LICENSE = "LGPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=6c9432eab6a070a936cf9da6191d6db6"

SRCREV = "89225b5ef6293d038e633414dd2ea917a99aea74"
SRC_URI = "git://gitlab.com/tango-controls/${BPN}.git;protocol=https;branch=main"

S = "${WORKDIR}/git"

inherit cmake

BBCLASSEXTEND = "nativesdk"
