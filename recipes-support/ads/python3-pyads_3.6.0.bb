SUMMARY = "This is a python wrapper for TwinCATs ADS library"
HOMEPAGE = "https://github.com/stlehmann/pyads"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=774af9d8c3ecbeb6a847dfac4c056bb3"

SRC_URI = " \
        git://github.com/stlehmann/pyads;branch=master;protocol=https \
        file://fix_writing_of_nested_structs_472.patch \
	"
SRCREV = "20ce6b14fd4d7078f8603c950ef9f1c88862c524"

DEPENDS += "libads meson-native ninja-native"

do_copy_libads() {
    mkdir -p ${S}/src
    cp ${STAGING_LIBDIR}/libAdsLib.so ${S}/src/AdsLib.so
}
addtask copy_libads after do_prepare_recipe_sysroot before do_compile

do_configure:prepend() {
    sed -i '/if cls.platform_is_unix():/,/return True/d' ${S}/setup.py
}

INSANE_SKIP:${PN} = "already-stripped"

inherit python3native setuptools3_legacy

BBCLASSEXTEND = "native nativesdk"
