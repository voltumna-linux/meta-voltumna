SUMMARY = "Official C++ client API for PostgreSQL"
DESCRIPTION = "libpqxx is the C++ language binding for PostgreSQL. It builds \
on top of the C-level libpq library and provides a C++-native API centred \
around transactions."
HOMEPAGE = "https://pqxx.org/libpqxx/"
SECTION = "libs"

LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://COPYING;md5=23dba67383b24e616ba754c597a6b0dd"

SRC_URI = "git://github.com/jtv/libpqxx.git;protocol=https;branch=7.10;tag=${PV}"
SRCREV = "853bc0a48f0327d8670c1c0855f7abf731046319"

# The postgresql recipe (meta-oe) provides the libpq library and headers.
DEPENDS = "postgresql"
# For the SDK variant use the standalone libpq recipe instead: it provides
# nativesdk-libpq without dragging in the whole postgresql.
DEPENDS:class-nativesdk = "libpq"

inherit cmake

EXTRA_OECMAKE = " \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TEST=OFF \
    -DBUILD_DOC=OFF \
    -DSKIP_BUILD_TEST=ON \
"

# Upstream installs the shared library as libpqxx-<abi>.so (there is no
# full-version filename), which the default ${libdir}/lib*${SOLIBS} glob does
# not match, so the real ELF would land in -dev and trip the dev-elf QA check.
# Ship the ABI-named library in the main package and keep only the libpqxx.so
# linker symlink in -dev.
FILES:${PN} += "${libdir}/libpqxx-*.so"
FILES_SOLIBSDEV = "${libdir}/libpqxx.so"

UPSTREAM_CHECK_URI = "https://github.com/jtv/libpqxx/tags"
UPSTREAM_CHECK_REGEX = "archive/refs/tags/(?P<pver>\d+(\.\d+)+)\.tar"

BBCLASSEXTEND = "nativesdk"
