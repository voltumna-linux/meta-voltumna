LICENSE = "ZPL-2.1"
LIC_FILES_CHKSUM = "file://${WORKDIR}/mingw-w64-v${PV}/COPYING;md5=bb936f0e04d8f1e19ad545100cee9654"

COMPATIBLE_HOST = ".*-mingw.*"

SRC_URI = "${SOURCEFORGE_MIRROR}/project/mingw-w64/mingw-w64/mingw-w64-release/mingw-w64-v${PV}.tar.bz2"

SRC_URI[md5sum] = "cf5673f6d689bb5e02863e6284cc3d03"
SRC_URI[sha256sum] = "805e11101e26d7897fce7d49cbb140d7bac15f3e085a91e0001e80b2adaf48f0"

UPSTREAM_CHECK_URI = "http://sourceforge.net/projects/mingw-w64/files/mingw-w64/mingw-w64-release/"
UPSTREAM_CHECK_REGEX = "mingw-w64-v(?P<pver>(\d+[\.\-_]*)+)\.tar"


