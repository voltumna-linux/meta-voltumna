RDEPENDS_${PN}_remove = "volatile-binds"

PACKAGECONFIG_remove = " \
	firstboot \
	hibernate \
	ima \
	smack \
	sysvinit \
"

PACKAGECONFIG_append = " \
	coredump \
	elfutils \
	serial-getty-generator \
"

do_install_append() {
	# Make journal volatile
	rmdir ${D}/var/log/journal

	# Remove volatile directories creation
	rm -f ${D}${sysconfdir}/tmpfiles.d/00-create-volatile.conf

	# Disable coredump
	sed -i -e 's/.*Storage.*/Storage=none/g' -e 's/.*ProcessSizeMax.*/ProcessSizeMax=0/g' \
		${D}${sysconfdir}/systemd/coredump.conf

	# Adjust shadow files
	echo 'Z /etc/{g,}shadow 0640 root shadow - -' >>${D}${exec_prefix}/lib/tmpfiles.d/etc.conf
	
	# Set the right permission
	chmod 755 ${D}${datadir}/polkit-1/rules.d

	# Remove few files and directories
	rm ${D}${datadir}/factory/etc/issue \
		${D}${datadir}/factory/etc/pam.d/other \
		${D}${datadir}/factory/etc/pam.d/system-auth
	rmdir ${D}${datadir}/factory/etc/pam.d
}
