DESCRIPTION = "Intel QuickAssist Technology Library (QATlib)"
HOMEPAGE = "https://github.com/intel/qatlib"

LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=92d2169808b08940f5e4812d97a4ea88"

PROVIDES += "virtual/qat"
RPROVIDES:${PN} += "qat"

COMPATIBLE_MACHINE = 'null'
COMPATIBLE_HOST:x86-x32 = 'null'
COMPATIBLE_HOST:libc-musl:class-target = 'null'

SRC_URI = "git://github.com/intel/qatlib.git;protocol=https;branch=main"
SRCREV = "9e22a2a83336a5210d8aa4df7f054815c15bead1"

inherit autotools-brokensep systemd useradd

DEPENDS = "openssl zlib nasm-native numactl autoconf-archive-native"

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
