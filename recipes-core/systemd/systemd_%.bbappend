FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI += " \
	file://99-default.link \
	file://sulogin-force.conf \
	"

RDEPENDS_${PN}_remove = "volatile-binds"
RRECOMMENDS_${PN}_remove = "os-release"

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

EXTRA_OEMESON += "-Dnobody-user=nobody \
                  -Dnobody-group=nogroup \
                  "

USERADD_PARAM:${PN} += " \
	--uid 10000 --user-group --groups dialout --no-create-home \
	--home-dir / --shell /bin/nologin controls; \
	"

do_install_append() {
	# Copy file to set NamePolicy for network interfaces
	install -m 0644 ${WORKDIR}/99-default.link ${D}${systemd_unitdir}/network/

	# Don't ask password in case of file system corruption
	install -m 0755 -d ${D}${systemd_unitdir}/system/rescue.service.d \
		${D}${systemd_unitdir}/system/emergency.service.d
	install -m 0644 ${WORKDIR}/sulogin-force.conf \
		${D}${systemd_unitdir}/system/rescue.service.d
	install -m 0644 ${WORKDIR}/sulogin-force.conf \
		${D}${systemd_unitdir}/system/emergency.service.d

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
