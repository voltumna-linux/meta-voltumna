SUMMARY = "PostgreSQL client library (libpq), SDK variant"
DESCRIPTION = "Minimal build of PostgreSQL's C client library (libpq): the \
shared library, its public headers and the pkg-config file. Only the \
nativesdk variant is built, to provide libpq inside the SDK sysroot; the \
target keeps getting libpq from the full postgresql recipe (meta-oe)."
HOMEPAGE = "https://www.postgresql.org/"
SECTION = "libs"

LICENSE = "0BSD"
LIC_FILES_CHKSUM = "file://COPYRIGHT;md5=55760ee57ce4e51e4b57f0801ff032dd"

SRC_URI = "https://ftp.postgresql.org/pub/source/v${PV}/postgresql-${PV}.tar.bz2 \
    file://0002-Improve-reproducibility.patch \
    file://0003-configure.ac-bypass-autoconf-2.69-version-check.patch \
    file://0004-config_info.c-not-expose-build-info.patch \
"
SRC_URI[sha256sum] = "dd27f2b3c59e73ed14aa3324901242bf69a032a6347805f274e6260322d42979"

# The upstream tarball unpacks to postgresql-${PV}, not ${BP}.
S = "${UNPACKDIR}/postgresql-${PV}"

# bison/flex and zic are hard requirements of PostgreSQL's configure.
DEPENDS = "openssl bison-native flex-native tzcode-native"

inherit autotools pkgconfig

# Only the SDK variant is useful here: the target gets libpq from the
# postgresql recipe. Skipping the target variant also avoids two recipes
# shipping packages named libpq/libpq-dev.
BBCLASSEXTEND = "nativesdk"
COMPATIBLE_HOST = "null"
COMPATIBLE_HOST:class-nativesdk = "(.*)"

EXTRA_OECONF = " \
    --with-ssl=openssl \
    --without-readline \
    --without-zlib \
    --without-icu \
    --without-perl \
    --without-python \
    --without-tcl \
    --without-gssapi \
    --without-pam \
    --without-ldap \
    --without-libxml \
    --without-libxslt \
    --without-lz4 \
    --without-zstd \
    --without-systemd \
    --disable-nls \
    --disable-rpath \
"
# Note: no --without-uuid; in PG 17 --with-uuid requires an explicit flavour
# (e2fs/bsd/ossp) and rejects yes/no. Omitting it defaults to no uuid support.

# Build only what libpq needs (the port/common helper libraries and libpq
# itself) instead of the whole server. If this trips over generated headers,
# add 'oe_runmake -C src/include generated-headers' (needs perlnative) before
# the sub-makes, or fall back to plain 'oe_runmake'.
do_compile() {
    oe_runmake -C src/port
    oe_runmake -C src/common
    oe_runmake -C src/interfaces/libpq
}

do_install() {
    oe_runmake -C src/interfaces/libpq install DESTDIR=${D}

    # postgres_ext.h (and pg_config.h/pg_config_ext.h) are normally shipped by
    # 'make install' of src/include; libpq-fe.h includes postgres_ext.h and
    # libpq consumers (e.g. cmake's FindPostgreSQL) expect the pg_config ones.
    install -d ${D}${includedir}
    install -m 0644 ${S}/src/include/postgres_ext.h \
        ${B}/src/include/pg_config.h ${B}/src/include/pg_config_ext.h \
        ${D}${includedir}/

    # Keep the SDK package minimal: drop the sample pg_service.conf that
    # 'make install' of libpq puts under ${datadir}/postgresql.
    rm -rf ${D}${datadir}
}
