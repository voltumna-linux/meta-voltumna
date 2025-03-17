DESCRIPTION = "Runtime libraries from MinGW-w64 project"

require mingw-w64.inc

S = "${WORKDIR}/mingw-w64-v${PV}/mingw-w64-crt"
B = "${WORKDIR}/build-${TARGET_SYS}"

inherit autotools nativesdk

BUILDSDK_CPPFLAGS_append = " -isystem${STAGING_INCDIR}"

INHIBIT_DEFAULT_DEPS = "1"
DEPENDS = "nativesdk-mingw-w64-headers virtual/${TARGET_PREFIX}gcc "

PROVIDES += "virtual/nativesdk-libc"

# Work around pulling in eglibc for now...
PROVIDES += "virtual/nativesdk-libintl"

TOOLCHAIN_OPTIONS = " --sysroot=${STAGING_DIR_TARGET}"

do_configure() {
    oe_runconf
}

FILES_${PN} += "${exec_prefix}/libsrc"

