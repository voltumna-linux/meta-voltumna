DESCRIPTION = "Librnmshare"
LICENSE = "GPLv3"
LIC_FILES_CHKSUM = "file://LICENSE;md5=85d75ff3cae33e25c7870cfe04040d6c"

DEPENDS += "librnmdpdk"

SRC_URI = "https://gitlab.elettra.eu/cs/lib/librnmshare/-/archive/${PV}/librnmshare-${PV}.tar.bz2"
SRC_URI[sha256sum] = "2aff9b05de717fecabb12f7e579cb0e987fa0a03aac09aa942d1141d4d3b687a"

do_install() {
	oe_runmake PREFIX=${D}${prefix} install
}

BBCLASSEXTEND = "native nativesdk"
