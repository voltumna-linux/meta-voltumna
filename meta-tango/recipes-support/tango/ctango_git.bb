DESCRIPTION = "TANGO is an object oriented distributed control system using CORBA \
(synchronous and asynchronous communication) and zeromq (event based communication)"
HOMEPAGE = "http://www.tango-controls.org"
LICENSE = "LGPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=6c9432eab6a070a936cf9da6191d6db6"

DEPENDS += "cpptango"

SRCREV = "0d2aba05c230bf63489c463c8550ec2a8d1507dc"
SRC_URI = "git://gitlab.com/tango-controls/C_Binding.git;protocol=https;branch=master \
	file://ctango_Makefile.patch \
	"

S = "${WORKDIR}/git"

do_compile() {
	oe_runmake "TANGO_HOME=${PKG_CONFIG_SYSROOT_DIR}${prefix}" "OS=" "INSTALL_BASE=${D}${prefix}" libc_tango.so
}

do_install() {
	oe_runmake "TANGO_HOME=${PKG_CONFIG_SYSROOT_DIR}${prefix}" "OS=" "INSTALL_BASE=${D}${prefix}"
}

BBCLASSEXTEND = "nativesdk"
