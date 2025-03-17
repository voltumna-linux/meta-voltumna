SUMMARY = "The benchmark utility to measure the performance of CPU"

LICENSE = "CLOSED"
LIC_FILES_CHKSUM = "file://LICENSE.md;md5=0a18b17ae63deaa8a595035f668aebe1"

SRC_URI = "git://github.com/eembc/coremark.git;branch=main;protocol=https"
SRCREV = "d5fad6bd094899101a4e5fd53af7298160ced6ab"

S = "${WORKDIR}/git"
TARGET_CC_ARCH += "${LDFLAGS}"

do_compile() {
	make compile
}

do_install() {
	install -d ${D}${bindir}
	install -m 0755 coremark.exe ${D}${bindir}
	mv ${D}${bindir}/coremark.exe ${D}${bindir}/coremark
}

COMPATIBLE_HOST = '(i.86|x86_64|arm|aarch64).*-linux'

SRC_URI[sha256sum] = "d003ed54134a0d365c0d5d8dc828432d610d1d1f77b8f58457cf1e599ad13f17"

