DESCRIPTION = "TANGO is an object oriented distributed control system using CORBA \
(synchronous and asynchronous communication) and zeromq (event based communication)"
HOMEPAGE = "http://www.tango-controls.org"
LICENSE = "LGPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=8195c2d9416e5fc98eb30ee334511b73"

DEPENDS += "omniorb-native omniorb tango-idl cppzmq libjpeg-turbo doxygen-native graphviz-native"
RDEPENDS_${PN} += "omniorb"

DEFAULT_PREFERENCE = "-1"

SRCREV = "40d901c63ec16596a3198747fce4846277927ec1"
SRC_URI = " \
	gitsm://gitlab.com/tango-controls/cppTango.git;protocol=https;branch=main;nobranch=1 \
	"

S = "${WORKDIR}/git"

EXTRA_OECMAKE += " \
	-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
	-DTANGO_USE_TELEMETRY=OFF"
EXTRA_OECMAKE_BUILD = "doc"

do_install_append() {
	install -d ${D}${docdir}/${BPN}
	cp -R ${B}/doc_html ${D}${docdir}/${BPN}/
}

inherit cmake python3native pkgconfig

BBCLASSEXTEND = "nativesdk"
