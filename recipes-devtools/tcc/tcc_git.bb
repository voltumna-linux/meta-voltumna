SUMMARY = "tinyCC - Tiny C Compiler"
HOMEPAGE = "https://bellard.org/tcc/"
LICENSE = "LGPL-2.1-or-later"
LIC_FILES_CHKSUM = "file://COPYING;md5=dcf3c825659e82539645da41a7908589"

DEPENDS += "tcc-native"

SRC_URI = " \
    git://repo.or.cz/tinycc.git;protocol=https;branch=mob \
    file://0001-Use-a-variable-for-c2str.exe-tool.patch \
    "
SRCREV = "904e95cbdf0248a57e5f8675ff10d17c59f5adbe"

# Upstream's release_0_9_XX tags do not follow the 1.0 version of this recipe
# and the mob branch carries no usable tags at all: track new commits instead
# and let devtool update SRCREV.
UPSTREAM_CHECK_COMMITS = "1"

PACKAGES =+ "libtcc"
FILES:libtcc += "${libdir}/libtcc.so.1"

RDEPENDS:${PN} += "libtcc"

EXTRA_OEMAKE:class-target = " \
    CONFIG_debug=no CONFIG_rpath=no \
    C2STR=${STAGING_BINDIR_NATIVE}/c2str.exe \
    XTCC=${STAGING_BINDIR_NATIVE}/tcc \
    "

do_install:append:class-native() {
    install ${B}/c2str.exe ${D}${bindir} 
}

do_install:append() {
    # Move headers in the right directory
    mv ${D}${libdir}/tcc/include/*.h ${D}${includedir}

    # Remove useless things
    rm -fr ${D}${libdir}/tcc ${D}${libdir}/tcc/*.o

    # Create symlink for the library
    mv ${D}${libdir}/libtcc.so ${D}${libdir}/libtcc.so.1
    ln -srn ${D}${libdir}/libtcc.so.1 ${D}${libdir}/libtcc.so
}

inherit autotools

BBCLASSEXTEND = "native nativesdk"
