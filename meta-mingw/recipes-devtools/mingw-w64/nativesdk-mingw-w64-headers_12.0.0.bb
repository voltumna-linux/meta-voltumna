DESCRIPTION = "Header files from the MingGW-w64 project"

require mingw-w64.inc

S = "${UNPACKDIR}/mingw-w64-v${PV}/mingw-w64-headers"
B = "${WORKDIR}/build-${TARGET_SYS}"

inherit autotools nativesdk

INHIBIT_DEFAULT_DEPS = "1"
DEPENDS = ""

do_configure() {
	oe_runconf
}

do_compile() {
	:
}

do_install:append() {
    # install correct pthread headers
    install -m 0644 -t ${D}${includedir} ${S}/../mingw-w64-libraries/winpthreads/include/*.h
}

FILES:${PN} += "${exec_prefix}/${TARGET_SYS}"
