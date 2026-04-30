require libmpc.inc

DEPENDS = "gmp mpfr"

LIC_FILES_CHKSUM = "file://COPYING.LESSER;md5=e6a600fd5e1d9cbde2d983680233ad02"
SRC_URI = "${GNU_MIRROR}/mpc/mpc-${PV}.tar.xz"

SRC_URI[sha256sum] = "3210b3a546b1cb00c296ca360891d7740ee6ff06deb02a27a35b20cd3c0bb1a5"

S = "${UNPACKDIR}/mpc-${PV}"
BBCLASSEXTEND = "native nativesdk"

