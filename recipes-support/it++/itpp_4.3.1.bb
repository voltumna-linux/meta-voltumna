DESCRIPTION = "IT++ is a C++ library of mathematical, signal processing and communication classes and functions"
HOMEPAGE = "http://itpp.sourceforge.net/"
LICENSE = "GPLv3"
LIC_FILES_CHKSUM = "file://COPYING;md5=d32239bcb673463ab874e80d47fae504"

SRC_URI = "https://downloads.sourceforge.net/project/itpp/itpp/4.3.1/itpp-4.3.1.tar.gz"

SRC_URI[md5sum] = "99c00a331276dae7b733067dd540e093"
SRC_URI[sha256sum] = "15333863c837dba1a0b3e6e84b5a2394e44bb62e3b751521b94f9b65bbf0ad91"

do_install:append() {
    sed -i "s,${RECIPE_SYSROOT},,g" ${D}${bindir}/itpp-config ${D}${libdir}/pkgconfig/itpp.pc
}

inherit cmake

BBCLASSEXTEND = "native nativesdk"
