DESCRIPTION = "Intel RDT (Resource Director Technology)"
HOMEPAGE = "https://github.com/intel/intel-cmt-cat"

LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=4b63c65942e1c16fd897f8cd20abebf8"

SRC_URI = " \
	git://github.com/intel/intel-cmt-cat;protocol=https;branch=master \
	file://cat-avoid-strip.patch \
	"
SRCREV = "dc984e1b74f05a216f56210d75e5949bc3ee7a6e"

S = "${WORKDIR}/git"

COMPATIBLE_HOST = '(x86_64).*-linux'
COMPATIBLE_HOST:libc-musl = "null"

export EXTRA_CFLAGS = "${CFLAGS}"
export EXTRA_LDFLAGS = "${LDFLAGS}"

do_install() {
	oe_runmake install PREFIX=${D}${prefix} NOLDCONFIG=y

	install -d ${D}${datadir}
	mv ${D}/usr/man  ${D}${datadir}/
}
