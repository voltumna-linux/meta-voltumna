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
	# Add an additional link to lib
	ln -sr ${D}/lib ${D}/lib${SITEINFO_BITS}

	# Install issue
	install -d ${D}${sysconfdir}
	cat <<-__EOF__ > ${D}${sysconfdir}/issue
	\S{NAME} \S{VERSION_ID} \S{MACHINE} \4{${@d.getVar('PRIMARY_NETIF')}} \l
	__EOF__

	# Add two scripts
	install -m 755 ${WORKDIR}/factory-reset ${D}/usr/sbin
	install -m 755 ${WORKDIR}/etcdiff ${D}/usr/bin
}
