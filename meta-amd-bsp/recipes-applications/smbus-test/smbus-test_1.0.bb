DESCRIPTION = "Sample application for AMD SMBUS driver"
SECTION = "applications"
LICENSE = "BSD | GPLv2"
DEPENDS = "readline"
LIC_FILES_CHKSUM = "file://smbus-test.c;endline=29;md5=8e7a9706367d146e5073510a6e176dc2"

SRC_URI = "file://smbus-test.c \
           file://i2c-dev.h \
          "

S = "${WORKDIR}"

TARGET_CC_ARCH += "${LDFLAGS}"

do_compile() {
	${CC} smbus-test.c -o smbus-test -lreadline
}

do_install() {
	install -d ${D}${bindir}
	install -m 0755 smbus-test ${D}${bindir}
}
