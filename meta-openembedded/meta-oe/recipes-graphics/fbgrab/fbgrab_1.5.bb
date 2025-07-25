SUMMARY = "FBGrab is a framebuffer screenshot program"
HOMEPAGE = "https://github.com/GunnarMonell/fbgrab"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=ea5bed2f60d357618ca161ad539f7c0a"
SECTION = "console/utils"
DEPENDS = "libpng zlib"
SRC_URI = "git://github.com/GunnarMonell/fbgrab.git;protocol=https;branch=master"

SRCREV = "f43ce6d5ce48fb01360eaa7c4a92c2573a1d02f8"

do_configure:prepend() {
    sed \
        -e 's|$(DESTDIR)/usr/bin/|$(DESTDIR)${bindir}/|g' \
        -e 's|$(DESTDIR)/usr/man/|$(DESTDIR)${mandir}/|g' \
        -i ${S}/Makefile
}

do_install() {
    oe_runmake 'DESTDIR=${D}' install
}
