DESCRIPTION = "Sample application for AMD RTC driver"
SECTION = "applications"
LICENSE = "BSD"
DEPENDS = "readline"
LIC_FILES_CHKSUM = "file://rtc-test.c;md5=ab350f4f921bfc19f7b7938a07f5688a"

SRC_URI = "file://rtc-test.c"

S = "${WORKDIR}"

TARGET_CC_ARCH += "${LDFLAGS}"

do_compile() {
	${CC} rtc-test.c -o rtc-test -lreadline
}

do_install() {
	install -d ${D}${bindir}
	install -m 0755 rtc-test ${D}${bindir}
}
