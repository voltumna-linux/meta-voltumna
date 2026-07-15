DESCRIPTION = "TANGO is an object oriented distributed control system using CORBA \
(synchronous and asynchronous communication) and zeromq (event based communication)"
HOMEPAGE = "http://www.tango-controls.org"
LICENSE = "LGPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3000208d539ec061b899bce1d9ce9404"

#DEPENDS += "omniorb-native omniorb tango-idl cppzmq libjpeg-turbo doxygen-native graphviz-native"
DEPENDS += "omniorb-native omniorb tango-idl cppzmq libjpeg-turbo" 
RDEPENDS:${PN} += "omniorb"

DEFAULT_PREFERENCE = "-1"

SRCREV = "62f0ce4232478fca2261782138e0ea1aacde005e"
SRC_URI = " \
	gitsm://gitlab.com/tango-controls/cppTango.git;protocol=https;nobranch=1 \
        file://0001-Fix-portability-bugs-on-big-endian-and-strict-alignm-10.3.patch \
	"

PACKAGECONFIG ?= ""
PACKAGECONFIG[telemetry] = "-DTANGO_USE_TELEMETRY=ON,-DTANGO_USE_TELEMETRY=OFF,opentelemetry-cpp"

EXTRA_OECMAKE += " \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    "
#EXTRA_OECMAKE_BUILD = "doc"
#
#do_install:append() {
#	install -d ${D}${docdir}/${BPN}
#	cp -R ${B}/doc_html ${D}${docdir}/${BPN}/
#}

inherit cmake python3native pkgconfig

BBCLASSEXTEND = "nativesdk"
