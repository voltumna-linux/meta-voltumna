DESCRIPTION = "Sample application for AMD Watchdog driver"
SECTION = "applications"
LICENSE = "BSD"
DEPENDS = "readline"
LIC_FILES_CHKSUM = "file://watchdog-test.c;md5=1d81025de7376754875ee74378f07d7a"

SRC_URI = "file://watchdog-test.c"

S = "${WORKDIR}"

TARGET_CC_ARCH += "${LDFLAGS}"

do_compile() {
	${CC} watchdog-test.c -o watchdog-test -lreadline
}

do_install() {
	install -d ${D}${bindir}
	install -m 0755 watchdog-test ${D}${bindir}
}
