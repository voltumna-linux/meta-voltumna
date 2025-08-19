DESCRIPTION = "Tango CORBA IDL file"
HOMEPAGE = "http://www.tango-controls.org"
LICENSE = "LGPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=6c9432eab6a070a936cf9da6191d6db6"

DEFAULT_PREFERENCE = "-1"

SRCREV = "e8348a4f605cf1fd07e409bb7a474d3a3b68c21c"
SRC_URI = "git://gitlab.com/tango-controls/${BPN}.git;protocol=https;branch=main"

S = "${WORKDIR}/git"

inherit cmake

BBCLASSEXTEND = "nativesdk"
