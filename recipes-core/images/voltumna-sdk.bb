require include/voltumna.inc

# IMAGE_INSTALL_append += "kernel-devsrc"
TOOLCHAIN_HOST_TASK_append_arm += "nativesdk-dtc"

SDKIMAGE_FEATURES += "dev-pkgs doc-pkgs dbg-pkgs tools-sdk tools-debug tools-profile"
SDK_ARCHIVE_TYPE = "tar.xz"
SDK_ARCHIVE_TYPE_sdkmingw32 = "zip"

install_adjustps1_into_sdk() {
	mkdir -p ${SDK_OUTPUT}${SDKPATHNATIVE}/environment-setup.d/
	cat <<-__EOF__ > ${SDK_OUTPUT}${SDKPATHNATIVE}/environment-setup.d/adjust-ps1.sh
	export debian_chroot=\$(echo \${BASH_SOURCE[1]} | sed 's/.*environment-setup-\(.*\)-voltumna-linux.*/\1/')
	__EOF__
}

install_adjustps1_into_sdk_sdkmingw32() {
	true
}

POPULATE_SDK_POST_TARGET_COMMAND += " install_adjustps1_into_sdk;"
