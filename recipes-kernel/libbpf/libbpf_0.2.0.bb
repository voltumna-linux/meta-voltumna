SUMMARY = "Library for BPF handling"
DESCRIPTION = "Library for BPF handling"
HOMEPAGE = "https://github.com/libbpf/libbpf"
SECTION = "libs"
LICENSE = "LGPL-2.1-or-later"

# There is a typo in the filename, LPGL should really be LGPL.
# Keep this until the correct name is set upstream.
LIC_FILES_CHKSUM = "file://../LICENSE.LPGL-2.1;md5=b370887980db5dd40659b50909238dbd"

DEPENDS = "zlib elfutils"

SRC_URI = "git://github.com/libbpf/libbpf.git;protocol=https;branch=master"
SRCREV = "d1fd50d475779f64805fdc28f912547b9e3dee8a"

# Backported from version 0.4
SRC_URI += "file://0001-install-don-t-preserve-file-owner.patch"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_HOST = "(x86_64|i.86|aarch64|riscv64|powerpc64).*-linux"

S = "${WORKDIR}/git/src"

EXTRA_OEMAKE += "DESTDIR=${D} LIBDIR=${libdir} INCLUDEDIR=${includedir}"
EXTRA_OEMAKE:append:class-native = " UAPIDIR=${includedir}"

inherit pkgconfig

do_compile() {
	oe_runmake
}

do_install() {
	oe_runmake install
}

do_install:append:class-native() {
	oe_runmake install_uapi_headers
}

BBCLASSEXTEND = "native nativesdk"
