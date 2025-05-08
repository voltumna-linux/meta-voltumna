require include/voltumna.inc
VARIANT = "Voltumna (Development)"

IMAGE_FEATURES += "debug-tweaks \
	${@bb.utils.contains('DISTRO_FEATURES', 'api-documentation', 'doc-pkgs', '', d)}"

IMAGE_INSTALL_append += " info man-pages"

# To keep in sync with SDK
IMAGE_INSTALL_append = " binutils cpp gcc libgcc-dev g++ libstdc++-dev libgomp-dev libasan-dev libubsan-dev"
IMAGE_INSTALL_append_arm += " dtc"
IMAGE_INSTALL_append_x86 += " liblsan-dev libtsan-dev"
IMAGE_INSTALL_append_x86-64 += " liblsan-dev libtsan-dev"

# Specific to SDE
IMAGE_INSTALL_append += " binutils-symlinks cpp-symlinks gcc-symlinks g++-symlinks \
	autoconf automake gettext libtool pkgconfig diffutils quilt git make cmake meson \
	devmem2 gzip kernel-devsrc prepare-kernel-devsrc glib-2.0-utils \
	powertop gdbserver valgrind"

install_sdk_sh() {
	install -d ${IMAGE_ROOTFS}${sysconfdir}/profile.d
	cat <<-__EOF__ >> ${IMAGE_ROOTFS}${sysconfdir}/profile.d/sdk.sh
	export MAKEFLAGS=-j\`getconf _NPROCESSORS_ONLN\`
	__EOF__
}

# export LDPATH="-Wl,--dynamic-linker=\`ls /lib/ld-linux*.so*\`"
# export CC="${TARGET_PREFIX}gcc ${TARGET_CC_ARCH} \${LDPATH}"
# export CXX="${TARGET_PREFIX}g++ ${TARGET_CC_ARCH} \${LDPATH}"

install_environment_setup_sh() {
	# Make compilation consistent between SDE and SDK
	target_cflags="`echo ${TARGET_CFLAGS} | sed -n 's,\(.*\) -fmacro.*,\1,p'`"
	target_cxxflags="`echo ${TARGET_CXXFLAGS} | sed -n 's,\(.*\) -fmacro.*,\1,p'`"
	target_ldflags="`echo ${TARGET_LDFLAGS} | sed -n 's,\(.*\) -fmacro.*,\1,p'`"
	target_cppflags="`echo ${TARGET_CPPFLAGS} | sed -n 's,\(.*\) -fmacro.*,\1,p'`"
	install -d ${IMAGE_ROOTFS}${sysconfdir}/profile.d
	cat <<-__EOF__ >> ${IMAGE_ROOTFS}${sysconfdir}/profile.d/environment-setup.sh
	export SDKTARGETSYSROOT=""
	export CC="${TARGET_PREFIX}gcc ${TARGET_CC_ARCH}"
	export CXX="${TARGET_PREFIX}g++ ${TARGET_CC_ARCH}"
	export CPP="${TARGET_PREFIX}gcc -E ${TARGET_CC_ARCH}"
	export AS="${TARGET_PREFIX}as ${TARGET_AS_ARCH}"
	export LD="${TARGET_PREFIX}ld ${TARGET_LD_ARCH}"
	export GDB=${TARGET_PREFIX}gdb
	export STRIP=${TARGET_PREFIX}strip
	export RANLIB=${TARGET_PREFIX}ranlib
	export OBJCOPY=${TARGET_PREFIX}objcopy
	export OBJDUMP=${TARGET_PREFIX}objdump
	export READELF=${TARGET_PREFIX}readelf
	export AR=${TARGET_PREFIX}ar
	export NM=${TARGET_PREFIX}nm
	export M4=m4
	export TARGET_PREFIX=${TARGET_PREFIX}
	export CONFIGURE_FLAGS="--target=${TARGET_SYS} --host=${TARGET_SYS} --build=${TARGET_ARCH}-linux"
	export CFLAGS="${target_cflags}"
	export CXXFLAGS="${target_cxxflags}"
	export LDFLAGS="${target_ldflags}"
	export CPPFLAGS="${target_cppflags}"
	export OECORE_DISTRO_VERSION="${DISTRO_VERSION}"
	export OECORE_SDK_VERSION="${SDK_VERSION}"
	export ARCH=${ARCH}
	export CROSS_COMPILE=${TARGET_PREFIX}
	export OECORE_TUNE_CCARGS="${TUNE_CCARGS}"
	__EOF__
}

set_killuserprocess() {
	sed -ie 's,#KillUserProcesses=yes,KillUserProcesses=no,g' ${IMAGE_ROOTFS}${sysconfdir}/systemd/logind.conf
}

ROOTFS_POSTPROCESS_COMMAND += " install_sdk_sh; install_environment_setup_sh; set_killuserprocess;"
MACHINE_FEATURES:remove = "qemu-usermode"
