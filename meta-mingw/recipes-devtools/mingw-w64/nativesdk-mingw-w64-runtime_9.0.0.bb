DESCRIPTION = "Runtime libraries from MinGW-w64 project"

require mingw-w64.inc

S = "${WORKDIR}/mingw-w64-v${PV}/mingw-w64-crt"
B = "${WORKDIR}/build-${TARGET_SYS}"

inherit autotools nativesdk

BUILDSDK_CPPFLAGS:append = " -isystem${STAGING_INCDIR}"

INHIBIT_DEFAULT_DEPS = "1"
DEPENDS = "nativesdk-mingw-w64-headers virtual/${TARGET_PREFIX}gcc "

PROVIDES += "virtual/nativesdk-libc"

# Work around pulling in eglibc for now...
PROVIDES += "virtual/nativesdk-libintl"

TOOLCHAIN_OPTIONS = " --sysroot=${STAGING_DIR_TARGET}"

EXTRA_OECONF:x86-64 = "--disable-lib32"

do_configure() {
    oe_runconf
}

FILES:${PN} += "${exec_prefix}/libsrc"

