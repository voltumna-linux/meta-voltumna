require include/voltumna.inc

IMAGE_FEATURES += "debug-tweaks bash-completion-pkgs \
	${@bb.utils.contains('DISTRO_FEATURES', 'api-documentation', 'doc-pkgs', '', d)}"

IMAGE_INSTALL_append += " info man-pages"

# To keep in sync with SDK
IMAGE_INSTALL_append = " binutils cpp gcc libgcc-dev g++ libstdc++-dev libgomp-dev libasan-dev libubsan-dev"
IMAGE_INSTALL_append_arm += " dtc"

# Specific to SDE
IMAGE_INSTALL_append += " binutils-symlinks cpp-symlinks gcc-symlinks g++-symlinks \
	autoconf automake gettext libtool pkgconfig diffutils quilt git make cmake meson \
	devmem2 gzip kernel-devsrc prepare-kernel-devsrc glib-2.0-utils \
	perf powertop strace gdb gdbserver valgrind"

install_sdk_sh() {
	install -d ${IMAGE_ROOTFS}${sysconfdir}/profile.d
	cat <<-__EOF__ >> ${IMAGE_ROOTFS}${sysconfdir}/profile.d/sdk.sh
	export MAKEFLAGS=-j\`getconf _NPROCESSORS_ONLN\`
	__EOF__
}

install_environment_setup_sh() {
	# Make compilation consistent between SDE and SDK
#	TARGET_CFLAGS="${TARGET_CFLAGS%%-fdebug*}"
#	TARGET_CXXFLAGS="${TARGET_CXXFLAGS%%-fdebug*}"
#	export LDPATH="-Wl,--dynamic-linker=\`ls /lib/ld-linux*.so*\`"
#	export CC="${TARGET_PREFIX}gcc ${TARGET_CC_ARCH} \${LDPATH}"
#	export CXX="${TARGET_PREFIX}g++ ${TARGET_CC_ARCH} \${LDPATH}"
#	export CPP="${TARGET_PREFIX}gcc -E ${TARGET_CC_ARCH}"
#	export AS="${TARGET_PREFIX}as ${TARGET_AS_ARCH}"
#	export LD="${TARGET_PREFIX}ld ${TARGET_LD_ARCH}"
#	export GDB=${TARGET_PREFIX}gdb
#	export STRIP=${TARGET_PREFIX}strip
#	export RANLIB=${TARGET_PREFIX}ranlib
#	export OBJCOPY=${TARGET_PREFIX}objcopy
#	export OBJDUMP=${TARGET_PREFIX}objdump
#	export AR=${TARGET_PREFIX}ar
#	export NM=${TARGET_PREFIX}nm
#	export M4=m4
#	export TARGET_PREFIX=${TARGET_PREFIX}
#	export CONFIGURE_FLAGS="--target=${TARGET_SYS} --host=${TARGET_SYS} --build=${TARGET_ARCH}-linux"
#	export CFLAGS="$TARGET_CFLAGS"
#	export CXXFLAGS="$TARGET_CXXFLAGS"
#	export LDFLAGS="${TARGET_LDFLAGS}"
#	export CPPFLAGS="${TARGET_CPPFLAGS}"

	install -d ${IMAGE_ROOTFS}${sysconfdir}/profile.d
	cat <<-__EOF__ >> ${IMAGE_ROOTFS}${sysconfdir}/profile.d/environment-setup.sh
	export SDKTARGETSYSROOT=""
	__EOF__
}

ROOTFS_POSTPROCESS_COMMAND += " install_sdk_sh; install_environment_setup_sh;"
