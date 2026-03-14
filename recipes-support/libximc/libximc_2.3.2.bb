SUMMARY = "Library for Standa 8SMC4-USB controllers"
DESCRIPTION = "Library to interface Standa 8SMC4-USB controllers. \
Based on Standa libximc 2.3.2 available from http://files.xisupport.com/Software.en.html"
SECTION = "libs"

LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=6370da19fa5b48405ba554721dfb00ab"

S = "${WORKDIR}/git"
SRCREV = "09e6fd0c910d9f59e3288f352ca6b59acc7ffd5c"
SRC_URI = "git://gitlab.elettra.eu/cs/lib/libximc.git;protocol=https;branch=master"

TARGET_CC_ARCH += "${LDFLAGS}"

do_install() {
	oe_runmake install PREFIX=${D}${prefix}
}

BBCLASSEXTEND = "nativesdk"
