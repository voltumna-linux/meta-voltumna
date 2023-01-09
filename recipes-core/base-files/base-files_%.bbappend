FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://fstab \
	file://factory-reset \
	file://etcdiff \
	"

FILES:${PN} += "${sysconfdir}/profile.d/environment-setup.sh"

volatiles = ""
dirs1777 = "/tmp ${localstatedir}/tmp"
dirs755:remove = "${localstatedir}/local ${localstatedir}/volatile"
conffiles:remove = "${sysconfdir}/issue.net"

# Unset hostname  otherwise hostnamed refuses to set it when passed by DHCP
hostname = ""

inherit siteinfo

# Avoid to install default version of the issue and issue.net files
do_install_basefilesissue () {
	:
}

do_install:append() {
	# Make compilation consistent between SDE and SDK
#	REAL_TARGET_CFLAGS=`echo "${TARGET_CFLAGS}" | sed -n 's/\(.*\) -fmacro.*/\1/p'`
#	REAL_TARGET_CXXFLAGS=`echo "${TARGET_CXXFLAGS}" | sed -n 's/\(.*\) -fmacro.*/\1/p'`
#	REAL_TARGET_CPPFLAGS=`echo "${TARGET_CPPFLAGS}" | sed -n 's/\(.*\) -fmacro.*/\1/p'`
#	REAL_TARGET_LDFLAGS=`echo "${TARGET_LDFLAGS}" | sed -n 's/\(.*\) -fmacro.*/\1/p'`
	install -d ${D}${sysconfdir}/profile.d
	cat <<-__EOF__ > ${D}${sysconfdir}/profile.d/environment-setup.sh
	export CC="${TARGET_PREFIX}gcc ${TARGET_CC_ARCH}"
	export CXX="${TARGET_PREFIX}g++ ${TARGET_CC_ARCH}"
	export CPP="${TARGET_PREFIX}cpp ${TARGET_CC_ARCH}"
	export AS="${TARGET_PREFIX}as ${TARGET_AS_ARCH}"
	export LD="${TARGET_PREFIX}ld ${TARGET_LD_ARCH}"
	export GDB="${TARGET_PREFIX}gdb"
	export STRIP="${TARGET_PREFIX}strip"
	export RANLIB="${TARGET_PREFIX}ranlib"
	export OBJCOPY="${TARGET_PREFIX}objcopy"
	export OBJDUMP="${TARGET_PREFIX}objdump"
	export AR="${TARGET_PREFIX}ar"
	export NM="${TARGET_PREFIX}nm"
	export M4="m4"
	export CFLAGS="${TARGET_CFLAGS}"
	export CXXFLAGS="${TARGET_CXXFLAGS}"
	export CPPFLAGS="${TARGET_CPPFLAGS}"
	export LDFLAGS="${TARGET_LDFLAGS}"
	__EOF__

	# Add an additional link to lib
	ln -sr ${D}/lib ${D}/lib${SITEINFO_BITS}

	# Install issue
	cat <<-__EOF__ > ${D}${sysconfdir}/issue
	\S{NAME} \S{VERSION_ID} \S{MACHINE} \4{${@d.getVar('PRIMARY_NETIF')}} \l
	__EOF__

	# Add two scripts
	install -m 755 ${WORKDIR}/factory-reset ${D}/usr/sbin
	install -m 755 ${WORKDIR}/etcdiff ${D}/usr/bin
}
