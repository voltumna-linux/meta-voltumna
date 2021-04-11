require include/voltumna.inc

# IMAGE_INSTALL_append += "kernel-devsrc"
TOOLCHAIN_HOST_TASK_append_arm += "nativesdk-dtc"

SDKIMAGE_FEATURES += "dev-pkgs bash-completion-pkgs doc-pkgs dbg-pkgs tools-sdk tools-debug tools-profile"
SDK_ARCHIVE_TYPE = "tar.xz"
SDK_ARCHIVE_TYPE_sdkmingw32 = "zip"

install_adjust_debian_chroot_into_sdk() {
	mkdir -p ${SDK_OUTPUT}${SDKTARGETSYSROOT}/environment-setup.d/
	cat <<-__EOF__ > ${SDK_OUTPUT}${SDKTARGETSYSROOT}/environment-setup.d/adjust-debian-chroot.sh
	export debian_chroot="${SDK_NAME_PREFIX} ${MACHINE} ${SDK_VERSION}"
	__EOF__
}

install_adjust_debian_chroot_into_sdk_sdkmingw32() {
	true
}

kernel_related_stuff_cleanup() {
	rm -fr ${SDK_OUTPUT}${SDKTARGETSYSROOT}/usr/src/kernel	\
		${SDK_OUTPUT}${SDKTARGETSYSROOT}/usr/boot/*	\
		${SDK_OUTPUT}${SDKTARGETSYSROOT}/lib/modules/*
	
}

POPULATE_SDK_POST_TARGET_COMMAND += " install_adjust_debian_chroot_into_sdk; kernel_related_stuff_cleanup;"

#SDK_POST_INSTALL_COMMAND_append += '$SUDO_EXEC sh -c ". $target_sdk_dir/environment-setup-@REAL_MULTIMACH_TARGET_SYS@ && cd $target_sdk_dir/sysroots/@REAL_MULTIMACH_TARGET_SYS@/usr/src/kernel/ && make prepare scripts >/dev/null 2>&1"'
