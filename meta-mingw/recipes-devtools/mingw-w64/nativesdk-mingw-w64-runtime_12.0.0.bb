DESCRIPTION = "Runtime libraries from MinGW-w64 project"

require mingw-w64.inc

#SRC_URI += "file://0001-crt-Fix-a-typo-in-the-ucrt-__imp_vfscanf-assignment.patch;striplevel=2"

S = "${WORKDIR}/mingw-w64-v${PV}/mingw-w64-crt"
B = "${WORKDIR}/build-${TARGET_SYS}"

inherit autotools nativesdk

BUILDSDK_CPPFLAGS:append = " -isystem${STAGING_INCDIR}"

INHIBIT_DEFAULT_DEPS = "1"
DEPENDS = "nativesdk-mingw-w64-headers virtual/nativesdk-cross-cc "

PROVIDES += "virtual/nativesdk-libc"

# Work around pulling in eglibc for now...
PROVIDES += "virtual/nativesdk-libintl"

TOOLCHAIN_OPTIONS = " --sysroot=${STAGING_DIR_TARGET}"

EXTRA_OECONF:x86-64 = "--disable-lib32"

do_configure() {
    oe_runconf
}

FILES:${PN} += "${exec_prefix}/libsrc"

