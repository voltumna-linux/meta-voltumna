SUMMARY = "A simple, correct PEP517 package builder"
HOMEPAGE = "https://github.com/pypa/build"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=310439af287b0fb4780b2ad6907c256c"

SRC_URI[sha256sum] = "5aa4231ae0e807efdf1fd0623e07366eca2ab215921345a2e38acdd5d0fa0a74"

inherit pypi python_flit_core

DEPENDS += "python3-pyproject-hooks-native"

do_compile:class-native() {
    python_flit_core_do_manual_build
}

RDEPENDS:${PN} += " \
    python3-compression \
    python3-difflib \
    python3-ensurepip \
    python3-logging \
    python3-packaging \
    python3-pyproject-hooks \
    python3-tomllib \
    python3-venv \
"

BBCLASSEXTEND = "native nativesdk"
