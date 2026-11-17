SUMMARY = "MariaDB/MySQL client library (libmysqlclient), SDK variant"
DESCRIPTION = "Minimal build of the MariaDB C client library (libmariadb with \
the libmysqlclient compatibility symlinks): the shared library, its public \
headers, the pkg-config file and mysql_config. Only the nativesdk variant is \
built, to provide libmysqlclient inside the SDK sysroot; the target keeps \
getting libmysqlclient from the full mariadb recipe (meta-oe)."
HOMEPAGE = "https://mariadb.org/"
SECTION = "libs"

# The client library (libmariadb) is LGPL; the GPL COPYING file of the
# tarball covers the server, which is not built here.
LICENSE = "LGPL-2.1-only"
LIC_FILES_CHKSUM = "file://COPYING.LIB;md5=4fbd65380cdd255951079008b364516c"

# The same tarball as the mariadb recipe (meta-oe), so the client ABI in the
# SDK is exactly the one shipped on the target.
SRC_URI = "https://archive.mariadb.org/mariadb-${PV}/source/mariadb-${PV}.tar.gz"
SRC_URI[sha256sum] = "1bb254b106d0a7ca871cfa18fa6e18d4b80a7430f9ec9d1571ec4271a13def96"

UPSTREAM_CHECK_URI = "https://github.com/MariaDB/server/tags"

# libmariadb/ is the mariadb-connector-c sub-project embedded in the server
# source tree: it has its own top-level CMakeLists.txt and builds standalone,
# so the server (sql, storage engines, tools) is not configured at all.
S = "${UNPACKDIR}/mariadb-${PV}/libmariadb"

# Same link dependencies as the target libmariadb: libssl/libcrypto and zlib.
DEPENDS = "openssl zlib"

inherit cmake pkgconfig

# Only the SDK variant is useful here: the target gets libmysqlclient from the
# mariadb recipe. Skipping the target variant also avoids two recipes shipping
# packages named libmysqlclient/libmysqlclient-dev.
BBCLASSEXTEND = "nativesdk"
COMPATIBLE_HOST = "null"
COMPATIBLE_HOST:class-nativesdk = "(.*)"

EXTRA_OECMAKE = " \
    -DWITH_SSL=OPENSSL \
    -DWITH_EXTERNAL_ZLIB=ON \
    -DWITH_CURL=OFF \
    -DWITH_UNIT_TESTS=OFF \
    -DWITH_DOCS=OFF \
    -DWITH_MYSQLCOMPAT=ON \
    -DINSTALL_LAYOUT=RPM \
    -DINSTALL_BINDIR=bin \
    -DINSTALL_LIBDIR=${baselib} \
    -DINSTALL_INCLUDEDIR=include/mysql \
    -DINSTALL_PCDIR=${baselib}/pkgconfig \
    -DINSTALL_PLUGINDIR=${baselib}/mariadb/plugin \
"
# WITH_MYSQLCOMPAT adds the libmysqlclient.so/libmysqlclient_r.so symlinks to
# libmariadb.so, so link lines written for the classic MySQL client library
# keep working. The INSTALL_* overrides give the same filesystem layout as the
# target mariadb recipe (headers in /usr/include/mysql, library in ${libdir}).

do_configure:prepend() {
    # Keep the build sysroot out of the generated mariadb_config (the same
    # trick as meta-oe's mariadb.inc): @CMAKE_SYSROOT@ expands to nothing and
    # mariadb_config falls back to the directory it is run from, which keeps
    # it relocatable inside the SDK.
    sed -i -e "s:CMAKE_SYSROOT:CMAKE_SYSROOT_PLACE_HOLDER:g" \
        ${S}/mariadb_config/mariadb_config.c.in
}

do_install() {
    cmake_do_install

    # mysql_config is the tool most client build systems look for;
    # mariadb_config is its drop-in replacement for the common options
    # (--cflags, --libs, --include, --version, --variable=...). Copy it rather
    # than symlinking: mariadb_config derives its install prefix from
    # /proc/self/exe, which resolves symlinks to the real binary name.
    install -m 0755 ${D}${bindir}/mariadb_config ${D}${bindir}/mysql_config

    # Keep the SDK package minimal: the client plugins (auth, compression)
    # are not shipped, the target brings its own.
    rm -rf ${D}${libdir}/mariadb
}

# The config scripts belong to the development package, as mariadb.inc does
# with mysql_config: they are used at build time, not at runtime.
FILES:${PN}-dev += "${bindir}/mysql_config ${bindir}/mariadb_config"
