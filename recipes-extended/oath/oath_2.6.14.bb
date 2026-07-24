LICENSE = "GPL-3.0-only & LGPL-2.1-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=1ebbd3e34237af26da5dc08a4e440464"

SRC_URI = "http://download.savannah.nongnu.org/releases/oath-toolkit/oath-toolkit-${PV}.tar.gz"

S = "${UNPACKDIR}/${BPN}-toolkit-${PV}"
SRC_URI[sha256sum] = "8b1da365759f1249be57a82aec6e107f7b57dc77d813f96dc0aaf81624f28971"

inherit autotools pkgconfig

DEPENDS = "gtk-doc-native"
