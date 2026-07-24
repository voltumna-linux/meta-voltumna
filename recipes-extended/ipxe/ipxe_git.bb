DESCRIPTION = "Open source network boot firmware"
HOMEPAGE = "http://ipxe.org"
LICENSE = "GPL-2.0-only"
DEPENDS = "binutils-native perl-native mtools-native xz coreutils-native"
LIC_FILES_CHKSUM = "file://../COPYING.GPLv2;md5=b234ee4d69f5fce4486a80fdaf4a4263"

# syslinux has this restriction
COMPATIBLE_HOST:class-target = '(x86_64|i.86).*-(linux|freebsd.*)'

SRCREV = "a0bf3f1cc85aa2e8853b66e59f26e8f398d9ed4e"
PV = "2.0.0+git"
PR = "r0"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
    git://github.com/ipxe/ipxe.git;protocol=https;branch=master \
    file://ipxe-fix-hostcc-nopie-cflags.patch \
    "

S = "${UNPACKDIR}/${BB_GIT_DEFAULT_DESTSUFFIX}/src"

FILES:${PN} = "/usr/share/firmware/*.rom"

EXTRA_OEMAKE = ' \
    CROSS_COMPILE="${TARGET_PREFIX}" \
    EXTRA_HOST_CFLAGS="${BUILD_CFLAGS}" \
    EXTRA_HOST_LDFLAGS="${BUILD_LDFLAGS}" \
    NO_WERROR="1" \
'

do_compile() {
    # Makefile.housekeeping:111: GNU gold is unsuitable for building iPXE
    # Makefile.housekeeping:112: Use GNU ld instead
    sed -i 's#\(^LD.*$(CROSS_COMPILE)ld\)$#\1.bfd#g' -i ${S}/Makefile

    # Skip ISO/USB image generation - only ROM files are needed for Xen
    # and the ISO tools (genisoimage/xorrisofs) are not available
    sed -i 's|bin/ipxe.iso||;s|bin/ipxe.usb||' ${S}/Makefile

    oe_runmake
}

do_install() {
    install -d ${D}/usr/share/firmware
    install ${S}/bin/*.rom ${D}/usr/share/firmware/
}

TOOLCHAIN = "gcc"
