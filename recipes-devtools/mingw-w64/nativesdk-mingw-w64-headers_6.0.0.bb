DESCRIPTION = "Header files from the MingGW-w64 project"

require mingw-w64.inc

S = "${WORKDIR}/mingw-w64-v${PV}/mingw-w64-headers"
B = "${WORKDIR}/build-${TARGET_SYS}"

inherit autotools nativesdk

INHIBIT_DEFAULT_DEPS = "1"
DEPENDS = ""

PACKAGECONFIG ??= "secure-api"

PACKAGECONFIG[secure-api] = "--enable-secure-api,--disable-secure-api"

do_configure() {
	oe_runconf
}

do_compile() {
	:
}

do_install_append() {
    # install correct pthread headers
    install -m 0644 -t ${D}${includedir} ${S}/../mingw-w64-libraries/winpthreads/include/*.h
}

FILES_${PN} += "${exec_prefix}/${TARGET_SYS}"
