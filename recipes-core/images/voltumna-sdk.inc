require include/voltumna.inc

# IMAGE_INSTALL:append = " kernel-devsrc"
TOOLCHAIN_HOST_TASK:append:arm = " nativesdk-dtc"

SDKIMAGE_FEATURES:append = "dev-pkgs bash-completion-pkgs doc-pkgs dbg-pkgs tools-sdk tools-debug tools-profile"
SDK_ARCHIVE_TYPE = "tar.xz"
SDK_ARCHIVE_TYPE:sdkmingw32 = "zip"

install_man_sh() {
	mkdir -p ${SDK_OUTPUT}/${SDKTARGETSYSROOT}/environment-setup.d/
	cat <<-__EOF__ >> ${SDK_OUTPUT}${SDKTARGETSYSROOT}/environment-setup.d/man.sh
	export MANPATH=\$SDKTARGETSYSROOT/usr/share/man
	export INFOPATH=\$SDKTARGETSYSROOT/usr/share/info
	alias info='info -vinfopath-no-defaults=On'
	__EOF__
}

install_man_sh:sdkmingw32() {
	:
}

POPULATE_SDK_POST_TARGET_COMMAND:append = " install_man_sh;"
