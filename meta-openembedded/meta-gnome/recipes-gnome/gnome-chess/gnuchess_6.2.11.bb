SUMMARY = "GNU Chess is a chess-playing program."
HOMEPAGE = "http://www.gnu.org/software/chess/"
LICENSE = "GPL-3.0-only"

LIC_FILES_CHKSUM = "file://COPYING;md5=d32239bcb673463ab874e80d47fae504"

SRC_URI = "${GNU_MIRROR}/chess/${BP}.tar.gz"
SRC_URI[sha256sum] = "d81140eea5c69d14b0cfb63816d4b4c9e18fba51f5267de5b1539f468939e9bd"

inherit autotools gettext

do_configure:prepend() {
    touch ${S}/ABOUT-NLS
    touch ${S}/man/gnuchess.1
}

FILES:${PN} += "${datadir}"
