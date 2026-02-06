DESCRIPTION = "OmniORB High Performance ORB"
HOMEPAGE = "http://omniorb.sourceforge.net"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=1b422f7cda3870b9c4b040b68ba1c0fe"

DEPENDS += "omniorb-native python3 openssl"

SRC_URI = "http://downloads.sourceforge.net/omniorb/omniORB-${PV}.tar.bz2"
SRC_URI[sha256sum] = "79720d415d23cd8da99287a4ef4da0aa1bd34d3e4c7b1530715600adc5ed3dc3"
SRC_URI:append = "\
    file://0002-python-shebang.patch \
"

S = "${UNPACKDIR}/omniORB-${PV}"

EXTRA_OECONF += "--disable-longdouble --with-openssl"

CONFFILES:${PN} += "/etc/omniORB.cfg"
FILES:${PN}-dev += "${libdir}/python${PYTHON_BASEVERSION}"

do_compile () {
	export TOOLBINDIR=${STAGING_BINDIR_NATIVE}
	oe_runmake
}

do_compile:class-native () {
	oe_runmake
}

do_install:append () {
	install -d ${D}${sysconfdir}
	install -m 0644 ${S}/sample.cfg ${D}${sysconfdir}/omniORB.cfg

	# Set sane defaults
	sed -i 's,^traceThreadId.*,traceThreadId = 0,g' ${D}${sysconfdir}/omniORB.cfg
	sed -i 's,^traceTime.*,traceTime = 0,g' ${D}${sysconfdir}/omniORB.cfg
}

PARALLEL_MAKE = ""

inherit autotools python3native pkgconfig

BBCLASSEXTEND = "native nativesdk"
