SUMMARY = "Seamless operability between C++11 and Python"
HOMEPAGE = "https://github.com/pybind/pybind11"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=774f65abd8a7fe3124be2cdf766cd06f"

SRC_URI[sha256sum] = "ba6af10348c12b24e92fa086b39cfba0eff619b61ac77c406167d813b096d39a"

inherit pypi setuptools3

#DEPENDS = "boost"
#
#SRC_URI = "\
#    git://github.com/pybind/pybind11.git;branch=stable;protocol=https \
#"
#SRCREV = "a2e59f0e7065404b44dfe92a28aca47ba1378dc4"
#
#S = "${WORKDIR}/git"
#
#BBCLASSEXTEND = "native"
#
#EXTRA_OECMAKE = "-DPYBIND11_TEST=OFF -DPYBIND11_USE_CROSSCOMPILING=ON"
#
#inherit cmake setuptools3 python3native
#
#PIP_INSTALL_DIST_PATH = "${S}/dist"
#PIP_INSTALL_PACKAGE = "pybind11"
#
#do_configure() {
#	cmake_do_configure
#}
#
#do_compile() {
#	setuptools3_do_compile
#	cmake_do_compile
#}
#
#do_install() {
#	setuptools3_do_install
#	cmake_do_install
#}
#
#BBCLASSEXTEND = "native nativesdk"
