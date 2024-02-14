DESCRIPTION = "Intel PCM (Performance Counter Monitor)"
HOMEPAGE = "https://github.com/intel/pcm"

LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=2d30532c8a8478266a67f85322d8478e"

SRC_URI = " \
	git://github.com/intel/pcm;protocol=https;branch=master \
	file://pcm-avoid-strip.patch \
	"
SRCREV = "2612158f452469c59fe72e79e4cdf9f71d46a4b5"

S = "${WORKDIR}/git"

COMPATIBLE_HOST = '(x86_64).*-linux'
COMPATIBLE_HOST:libc-musl = "null"

do_install:append() {
	mv ${D}${docdir}/PCM ${D}${docdir}/pcm
	rm -fr ${D}${datadir}/licenses
}

FILES:${PN} += "${datadir}/pcm"

inherit cmake
