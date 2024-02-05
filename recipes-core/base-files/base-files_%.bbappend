FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI += " \
	file://fstab \
	file://factory-reset \
	file://etcdiff \
	"

FILES_${PN} += "${sysconfdir}/profile.d/environment-setup.sh"

volatiles = ""
dirs1777 = "/tmp ${localstatedir}/tmp"
dirs755_remove = "${localstatedir}/local ${localstatedir}/volatile"
conffiles_remove = "${sysconfdir}/issue.net"

# Unset hostname  otherwise hostnamed refuses to set it when passed by DHCP
hostname = ""

inherit siteinfo

# Avoid to install default version of the issue and issue.net files
do_install_basefilesissue () {
	:
}

do_install[vardeps] += "PRIMARY_NETIF"
do_install_append() {
	# Add an additional link to lib
	lnr ${D}/lib ${D}/lib${SITEINFO_BITS}

	# Install issue
	install -d ${D}${sysconfdir}
	cat <<-__EOF__ > ${D}${sysconfdir}/issue
	\S{NAME} \S{VERSION_ID} \S{MACHINE} \4{${@d.getVar('PRIMARY_NETIF')}}
	__EOF__

	# Add two scripts
	install -m 755 ${WORKDIR}/factory-reset ${D}/usr/sbin
	install -m 755 ${WORKDIR}/etcdiff ${D}/usr/bin
}

PACKAGE_ARCH = "${TUNE_PKGARCH}"
