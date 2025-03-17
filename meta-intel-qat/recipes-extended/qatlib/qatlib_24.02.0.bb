DESCRIPTION = "Intel QuickAssist Technology Library (QATlib)"
HOMEPAGE = "https://github.com/intel/qatlib"

LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=64dc5eee9d532c8a1633bb63ed0d1aac"

PROVIDES += "virtual/qat"
RPROVIDES:${PN} += "qat"

COMPATIBLE_MACHINE = 'null'
COMPATIBLE_HOST:x86-x32 = 'null'
COMPATIBLE_HOST:libc-musl:class-target = 'null'

SRC_URI = "git://github.com/intel/qatlib.git;protocol=https;branch=main"
SRCREV = "61178382110a5b93898e2a1d07c84aac9c695362"

S = "${WORKDIR}/git"

inherit autotools-brokensep systemd useradd

DEPENDS = "openssl zlib nasm-native"

USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "qat"

SYSTEMD_SERVICE:${PN} = "qat.service"

# The systemd unit path "/lib/systemd/system" cannot be correctly passed to build system of QATlib. So hardcode here.
# Checking "cross_compiling" is not smart and sometimes causes fatal error due to wrong path of ELF file interpreter.
EXTRA_OECONF += "systemdsystemunitdir=${systemd_system_unitdir} cross_compiling=yes"

do_compile:append () {
    oe_runmake samples
}

do_install:append () {
    oe_runmake 'DESTDIR=${D}' samples-install
}

FILES:${PN} += "${datadir}/qat"
