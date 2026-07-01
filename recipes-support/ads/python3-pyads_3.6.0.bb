SUMMARY = "This is a python wrapper for TwinCATs ADS library"
HOMEPAGE = "https://github.com/stlehmann/pyads"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=774af9d8c3ecbeb6a847dfac4c056bb3"

SRC_URI = " \
        git://github.com/stlehmann/pyads;branch=master;protocol=https \
	"
SRCREV = "20ce6b14fd4d7078f8603c950ef9f1c88862c524"
S = "${WORKDIR}/git"

DEPENDS += "libads meson-native ninja-native"

do_copy_libads() {
    mkdir -p ${S}/src
    cp ${STAGING_LIBDIR}/libAdsLib.so ${S}/src/AdsLib.so
}
addtask copy_libads after do_prepare_recipe_sysroot before do_compile

do_configure:prepend() {
    sed -i 's/^license = "MIT"/license = { text = "MIT" }/' ${S}/pyproject.toml
    sed -i '/^license-files = \[.*\]/d' ${S}/pyproject.toml
    sed -i '/if cls.platform_is_unix():/,/return True/d' ${S}/setup.py
    sed -i '/from setuptools.command.bdist_wheel import bdist_wheel, get_platform/d' ${S}/setup.py
    sed -i '/class CustomBDistWheel(bdist_wheel):/,/return impl_tag, abi_tag, plat_name/d' ${S}/setup.py
    sed -i '/"bdist_wheel": CustomBDistWheel,/d' ${S}/setup.py
}

INSANE_SKIP:${PN} = "already-stripped"

inherit python3native setuptools3_legacy

BBCLASSEXTEND = "native nativesdk"
