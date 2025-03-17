DESCRIPTION = "Tango CORBA IDL file"
HOMEPAGE = "http://www.tango-controls.org"
LICENSE = "LGPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=6c9432eab6a070a936cf9da6191d6db6"

DEFAULT_PREFERENCE = "-1"

SRCREV = "5a2f4b2e0e5c8a08ec9d9b0d9673c395d6876cc1"
SRC_URI = "git://gitlab.com/tango-controls/${BPN}.git;protocol=https;branch=main"

S = "${WORKDIR}/git"

inherit cmake

BBCLASSEXTEND = "nativesdk"
