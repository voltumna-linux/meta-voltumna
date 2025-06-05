DESCRIPTION = "Library for Gussian fitting"
LICENSE = "GPLv3"
LIC_FILES_CHKSUM = "file://LICENSE;md5=6f9f2aecf846d428f2b35d46d9c5ebe2"

DEPENDS += "gsl openblas"

SRC_URI = "https://gitlab.elettra.eu/cs/lib/libfit/-/archive/${PV}/libfit-${PV}.tar.bz2"
SRC_URI[sha256sum] = "2b279235c1e1de02e10a650336bb6c2bab5d013c31f79380af57cfbd2c767924"

do_install() {
	oe_runmake PREFIX=${D}${prefix} install
}

BBCLASSEXTEND = "native nativesdk"
