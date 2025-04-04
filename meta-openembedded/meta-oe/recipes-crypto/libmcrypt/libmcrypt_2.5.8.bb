SUMMARY = "Replacement for the old crypt() package and crypt(1) command, with extensions"
HOMEPAGE = "http://mcrypt.sourceforge.net/"
LICENSE = "LGPL-2.1-only"
LIC_FILES_CHKSUM = "file://COPYING.LIB;md5=bbb461211a33b134d42ed5ee802b37ff"
DEPENDS = "libtool"

SRC_URI = " \
    ${SOURCEFORGE_MIRROR}/project/mcrypt/Libmcrypt/${PV}/libmcrypt-${PV}.tar.gz \
    file://0001-fix-parameter-related-unexpected-error-in-gcc-15.0.1.patch \
"

SRC_URI[sha256sum] = "e4eb6c074bbab168ac47b947c195ff8cef9d51a211cdd18ca9c9ef34d27a373e"

UPSTREAM_CHECK_URI = "https://sourceforge.net/projects/mcrypt/files/Libmcrypt/"
UPSTREAM_CHECK_REGEX = "Libmcrypt/(?P<pver>\d+(\.\d+)+)/"

inherit autotools-brokensep gettext binconfig multilib_script

CFLAGS += "-Wno-error=implicit-int"

do_configure() {
        install -m 0755 ${STAGING_DATADIR_NATIVE}/gnu-config/config.guess ${S}
        install -m 0755 ${STAGING_DATADIR_NATIVE}/gnu-config/config.sub ${S}
        aclocal
        libtoolize --automake --copy --force
        autoconf
        autoheader
        automake -a
        oe_runconf
}

CLEANBROKEN = "1"

MULTILIB_SCRIPTS = "${PN}-dev:${bindir}/libmcrypt-config"
