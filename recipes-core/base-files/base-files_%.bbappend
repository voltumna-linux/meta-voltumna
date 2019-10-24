FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI += "file://fstab"

FILES_${PN} += "${sysconfdir}/profile.d/environment-setup.sh"

volatiles = ""
dirs1777 = "/tmp ${localstatedir}/tmp"
dirs755_remove = "${localstatedir}/local ${localstatedir}/volatile"
conffiles_remove = "${sysconfdir}/issue.net"

# Unset hostname  otherwise hostnamed refuses to set it when passed by DHCP
hostname = ""

inherit siteinfo

do_install_append() {
#	# Make compilation consistent between SDE and SDK
#	install -d ${D}${sysconfdir}/profile.d
#	TARGET_CFLAGS="${TARGET_CFLAGS%%-fdebug*}"
#	TARGET_CXXFLAGS="${TARGET_CXXFLAGS%%-fdebug*}"
#	cat <<-__EOF__ > ${D}${sysconfdir}/profile.d/environment-setup.sh
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
#	__EOF__

	# Add an additional link to lib
	lnr ${D}/lib ${D}/lib${SITEINFO_BITS}

	# Remove issue.net (ssh doesn't support \S{VARIABLE} 
	# and it isn't even enabled by default via Banner)
	rm -f ${D}/${sysconfdir}/issue.net

	# Replace issue
	cat <<-__EOF__ > ${D}${sysconfdir}/issue
	\S{NAME} \S{VERSION_ID} \S{MACHINE} \4{eth0} \l
	__EOF__
}
