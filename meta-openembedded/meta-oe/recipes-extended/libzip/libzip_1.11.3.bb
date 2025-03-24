DESCRIPTION = "libzip is a C library for reading, creating, and modifying zip archives."
HOMEPAGE = "https://libzip.org/"

LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=d8a9d2078f35e61cf1122ccd440687cf"

DEPENDS = "zlib bzip2"

PACKAGECONFIG[ssl] = "-DENABLE_OPENSSL=ON,-DENABLE_OPENSSL=OFF,openssl"
PACKAGECONFIG[lzma] = "-DENABLE_LZMA=ON,-DENABLE_LZMA=OFF,xz"
PACKAGECONFIG[gnutls] = "-DENABLE_GNUTLS=ON,-DENABLE_GNUTLS=OFF,gnutls nettle"
PACKAGECONFIG[zstd] = "-DENABLE_ZSTD=ON,-DENABLE_ZSTD=OFF,zstd"
PACKAGECONFIG[mbedtls] = "-DENABLE_MBEDTLS=ON,-DENABLE_MBEDTLS=OFF,mbedtls"
PACKAGECONFIG[examples] = "-DENABLE_EXAMPLES=ON,-DENABLE_EXAMPLES=OFF,"
PACKAGECONFIG[tools] = "-DENABLE_TOOLS=ON,-DENABLE_TOOLS=OFF,"
PACKAGECONFIG[tests] = "-DBUILD_REGRESS=ON,-DBUILD_REGRESS=OFF,"

PACKAGECONFIG ?= "ssl lzma tools examples"

inherit cmake

SRC_URI = "https://libzip.org/download/libzip-${PV}.tar.xz"

SRC_URI[sha256sum] = "9509d878ba788271c8b5abca9cfde1720f075335686237b7e9a9e7210fe67c1b"

BBCLASSEXTEND += "native"
