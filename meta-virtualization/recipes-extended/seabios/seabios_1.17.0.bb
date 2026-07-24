DESCRIPTION = "SeaBIOS"
HOMEPAGE = "http://www.coreboot.org/SeaBIOS"
LICENSE = "LGPL-3.0-only"
SECTION = "firmware"

inherit python3native

SRC_URI = " \
    https://www.seabios.org/downloads/seabios-${PV}.tar.gz \
    file://hostcc.patch \
    file://python3.patch \
    "
S = "${UNPACKDIR}/${PN}-${PV}"

LIC_FILES_CHKSUM = "file://COPYING;md5=d32239bcb673463ab874e80d47fae504         \
                    file://COPYING.LESSER;md5=6a6a8e020838b23406c81b19c1d46df6  \
                    "
SRC_URI[sha256sum] = "5159a35fac5c1579dd5d702001033c826ce45d30d3bd657ec1b2695455997712"

FILES:${PN} = "/usr/share/firmware"

DEPENDS += "util-linux-native file-native bison-native flex-native gettext-native acpica-native"

TUNE_CCARGS = ""
EXTRA_OEMAKE += "HOSTCC='${BUILD_CC}'"
EXTRA_OEMAKE += "CROSS_PREFIX=${TARGET_PREFIX}"

# Can not yet compile with clang e.g.
TOOLCHAIN = "gcc"

COMPATIBLE_HOST = "(i.86|x86_64).*-linux"

do_configure() {
    oe_runmake defconfig
}

do_compile() {
    unset CPP
    unset CPPFLAGS
    oe_runmake
}

do_install() {
    oe_runmake
    install -d ${D}/usr/share/firmware
    install -m 0644 out/bios.bin ${D}/usr/share/firmware/
}

