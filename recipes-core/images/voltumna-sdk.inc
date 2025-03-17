LICENSE = "MIT"
IMAGE_LINGUAS = "en-us"

SDKIMAGE_FEATURES = "${@bb.utils.contains('DISTRO_FEATURES', 'api-documentation', 'doc-pkgs', '', d)}"

IMAGE_INSTALL:append = " info man-pages"
IMAGE_INSTALL:append = " libasan-dev libubsan-dev"
IMAGE_INSTALL:append:intel-x86-common = " liblsan-dev libtsan-dev"

# To keep in sync with SDE
TOOLCHAIN_HOST_TASK:append = " nativesdk-make nativesdk-binutils nativesdk-cpp nativesdk-gcc \
	nativesdk-libgcc-dev nativesdk-g++ nativesdk-libstdc++-dev nativesdk-libgomp-dev \
	nativesdk-libasan-dev nativesdk-libubsan-dev nativesdk-clang nativesdk-python3-pylint"
TOOLCHAIN_HOST_TASK:append:arm = " nativesdk-dtc"
TOOLCHAIN_HOST_TASK:append:intel-x86-common = " nativesdk-liblsan-dev nativesdk-libtsan-dev"

SDK_ARCHIVE_TYPE = "tar.xz"
SDK_ARCHIVE_TYPE:sdkmingw32 = "zip"

install_man_sh() {
	mkdir -p ${SDK_OUTPUT}/${SDKPATHNATIVE}/environment-setup.d/
	cat <<-__EOF__ >> ${SDK_OUTPUT}${SDKPATHNATIVE}/environment-setup.d/man.sh
	export MANPATH=\$SDKTARGETSYSROOT/usr/share/man
	export INFOPATH=\$SDKTARGETSYSROOT/usr/share/info
	alias info='info -vinfopath-no-defaults=On'
	__EOF__
}

fix_linker_scripts() {
       for f in libm libc; do
               f=${SDK_OUTPUT}${SDKPATHNATIVE}${libdir_nativesdk}/${f}.so
	      test -f $f || continue
               sed -i "s#${SDKPATHNATIVE}##g" ${f}
       done
}

POPULATE_SDK_POST_HOST_COMMAND:append = " install_man_sh; fix_linker_scripts;"

inherit image
