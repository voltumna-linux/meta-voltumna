SUMMARY = "C implementation of the Raft consensus protocol"
DESCRIPTION = "Fully asynchronous C implementation of the Raft consensus \
protocol, with a pluggable I/O layer supporting libuv for production and \
in-memory transports for testing."
HOMEPAGE = "https://github.com/cowsql/raft"
LICENSE = "LGPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=51b0baf3ea280222685bbfd862de758b"

SRCREV = "9edb176a7924ce2b943cb56552366dc4b5a1a6b7"
SRC_URI = "git://github.com/cowsql/raft.git;branch=main;protocol=https"

PV = "0.22.1"

inherit autotools-brokensep pkgconfig

PACKAGECONFIG ??= "uv lz4"
PACKAGECONFIG[uv] = "--enable-uv,--disable-uv,libuv"
PACKAGECONFIG[lz4] = "--with-lz4,--without-lz4,lz4"

# Disable things not needed for production
EXTRA_OECONF = " \
    --disable-benchmark \
    --disable-example \
    --disable-debug \
    --disable-sanitize \
    --disable-fixture \
"

do_install:append() {
    rmdir --ignore-fail-on-non-empty ${D}${bindir}
}
