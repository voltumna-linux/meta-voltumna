SUMMARY = "cargo applet to build and install C-ABI compatible dynamic and static libraries."
HOMEPAGE = "https://crates.io/crates/cargo-c"
LICENSE = "MIT"
LIC_FILES_CHKSUM = " \
    file://LICENSE;md5=384ed0e2e0b2dac094e51fbf93fdcbe0 \
"

SRC_URI = "crate://crates.io/cargo-c/${PV};name=cargo-c"
SRC_URI[cargo-c.sha256sum] = "bd11efb38aee5930cabfe8d41465f22859b2af9071fa04d3642814cf1cc2bc75"
S = "${CARGO_VENDORING_DIRECTORY}/cargo-c-${PV}"

inherit cargo cargo-update-recipe-crates pkgconfig

DEPENDS = "openssl curl"

require ${BPN}-crates.inc

BBCLASSEXTEND = "native"
