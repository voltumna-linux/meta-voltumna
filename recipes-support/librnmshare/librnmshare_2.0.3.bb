DESCRIPTION = "Librnmshare"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=85d75ff3cae33e25c7870cfe04040d6c"

DEPENDS:append = "librnmdpdk"

SRC_URI = "https://gitlab.elettra.eu/cs/lib/librnmshare/-/archive/${PV}/librnmshare-${PV}.tar.bz2"
SRC_URI[sha256sum] = "71e61e5914894aea7a7d73eff2109abc39b2517b1d473cd3bc6a865931831f2d"

do_install() {
	oe_runmake PREFIX=${D}${prefix} install
}

PARALLEL_MAKE = ""

BBCLASSEXTEND = "nativesdk"
