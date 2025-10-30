SUMMARY = "open-source formatting library for C++"
DESCRIPTION = "{fmt} is an open-source formatting library for C++. It can be used as a safe and fast alternative to (s)printf and iostreams."
HOMEPAGE = "https://fmt.dev"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=b9257785fc4f3803a4b71b76c1412729"

SRC_URI = "git://github.com/fmtlib/fmt;branch=master;protocol=https;tag=${PV}\
           file://0001-Workaround-an-ABI-issue-in-spdlog.patch \
           file://0001-Fix-compilation-on-clang-21-libc-21-4477.patch \
           file://run-ptest \
           "
SRCREV = "40626af88bd7df9a5fb80be7b25ac85b122d6c21"

inherit cmake ptest

EXTRA_OECMAKE += "-DBUILD_SHARED_LIBS=ON"
EXTRA_OECMAKE += "${@bb.utils.contains('PTEST_ENABLED', '1', '-DFMT_TEST=ON', '', d)}"

do_install_ptest(){
	for t in ${B}/bin/*-test; do
		install $t ${D}${PTEST_PATH}/
	done
}

BBCLASSEXTEND = "native nativesdk"
