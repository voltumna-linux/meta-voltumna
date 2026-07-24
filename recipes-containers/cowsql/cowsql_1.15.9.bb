SUMMARY = "Distributed SQLite database using the Raft protocol"
DESCRIPTION = "cowsql is a C library that implements an embeddable and \
replicated SQL database engine with high availability and automatic \
failover, built on top of the Raft consensus protocol."
HOMEPAGE = "https://github.com/cowsql/cowsql"
LICENSE = "LGPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=728bf7a3521f8a76af96915eae595fd4"

SRCREV = "783815b901470e27b7dfbcce3a67c888dad19e78"
SRC_URI = "git://github.com/cowsql/cowsql.git;branch=main;protocol=https"

PV = "1.15.9"

DEPENDS = "sqlite3 libuv raft"

inherit autotools-brokensep pkgconfig

EXTRA_OECONF = " \
    --disable-debug \
    --disable-sanitize \
    --disable-backtrace \
    --disable-build-sqlite \
"

# Upstream enables -Werror; GCC 15 is stricter about const qualifiers
CFLAGS += "-Wno-error=discarded-qualifiers"

