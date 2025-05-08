LICENSE = "MIT"
IMAGE_LINGUAS = "en-us"

SDKIMAGE_FEATURES = "${@bb.utils.contains('DISTRO_FEATURES', 'api-documentation', 'doc-pkgs', '', d)}"

IMAGE_INSTALL_append += " info man-pages"
IMAGE_INSTALL_append += " libasan-dev libubsan-dev"
IMAGE_INSTALL_append_x86 += " liblsan-dev libtsan-dev"
IMAGE_INSTALL_append_x86-64 += " liblsan-dev libtsan-dev"

# To keep in sync with SDE
TOOLCHAIN_HOST_TASK_append = " nativesdk-binutils nativesdk-cpp nativesdk-gcc nativesdk-libgcc-dev \
	nativesdk-g++ nativesdk-libstdc++-dev nativesdk-libgomp-dev \
	nativesdk-libasan-dev nativesdk-libubsan-dev"
TOOLCHAIN_HOST_TASK_append_arm += "nativesdk-dtc"
TOOLCHAIN_HOST_TASK_append_x86 += " nativesdk-liblsan-dev nativesdk-libtsan-dev"
TOOLCHAIN_HOST_TASK_append_x86-64 += " nativesdk-liblsan-dev nativesdk-libtsan-dev"

SDK_ARCHIVE_TYPE = "tar.xz"
SDK_ARCHIVE_TYPE_sdkmingw32 = "zip"

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

POPULATE_SDK_POST_HOST_COMMAND_append += " install_man_sh; fix_linker_scripts;"

inherit image
