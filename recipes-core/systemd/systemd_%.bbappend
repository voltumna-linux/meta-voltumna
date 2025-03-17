FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://99-default.link \
	file://sulogin-force.conf \
	file://energy_perf_bias \
	file://energy_perf_bias.service \
	file://systemd-journal-upload.service \
	"

DEPENDS:append = " curl"
RDEPENDS:${PN}:remove = "volatile-binds"
RRECOMMENDS:${PN}:remove = "os-release"

PACKAGECONFIG:remove = " \
	firstboot \
	hibernate \
	ima \
	smack \
	sysvinit \
"

PACKAGECONFIG:append = " \
	coredump \
	elfutils \
	serial-getty-generator \
	journal-upload \
"

EXTRA_OEMESON += "-Dnobody-user=nobody \
                  -Dnobody-group=nogroup \
                  "

FILES:${PN}:append = " ${sbindir} ${systemd_unitdir}/system"

do_install:append() {
	# Disable parsing of the ip kernel command line parameter
	sed -i 's/enable systemd-network-generator.service/disable systemd-network-generator.service/' \
		${D}${systemd_unitdir}/system-preset/90-systemd.preset
	sed -i 's/Also=systemd-network-generator.service/#Also=systemd-network-generator.service/'  \
		${D}${systemd_unitdir}/system/systemd-networkd.service

	# Copy file to set NamePolicy for network interfaces
	install -m 0644 ${WORKDIR}/99-default.link ${D}${systemd_unitdir}/network/

	# Don't ask password in case of file system corruption
	install -m 0755 -d ${D}${systemd_unitdir}/system/rescue.service.d \
		${D}${systemd_unitdir}/system/emergency.service.d
	install -m 0644 ${WORKDIR}/sulogin-force.conf \
		${D}${systemd_unitdir}/system/rescue.service.d
	install -m 0644 ${WORKDIR}/sulogin-force.conf \
		${D}${systemd_unitdir}/system/emergency.service.d

	# Remove volatile directories creation
	rm -f ${D}${sysconfdir}/tmpfiles.d/00-create-volatile.conf

	# Disable coredump
	sed -i -e 's/.*Storage.*/Storage=none/g' -e 's/.*ProcessSizeMax.*/ProcessSizeMax=0/g' \
		${D}${sysconfdir}/systemd/coredump.conf

	# Make logs volatile
	sed -i -e 's/.*Storage.*/Storage=volatile/g' ${D}${sysconfdir}/systemd/journald.conf

	# Adjust shadow files
	echo 'Z /etc/{g,}shadow 0640 root shadow - -' >>${D}${exec_prefix}/lib/tmpfiles.d/etc.conf
	
	# Enforce /run/lock creation
	echo 'd /run/lock 0755 root root - -' >>${D}${exec_prefix}/lib/tmpfiles.d/tmp.conf

	# Set the right permission
	chmod 755 ${D}${datadir}/polkit-1/rules.d

	# Remove few files and directories
	rm ${D}${datadir}/factory/etc/issue \
		${D}${datadir}/factory/etc/pam.d/other \
		${D}${datadir}/factory/etc/pam.d/system-auth
	rmdir ${D}${datadir}/factory/etc/pam.d

	# Add script energy_perf_bias
	install -d ${D}${sbindir}
	install -m 0755 ${WORKDIR}/energy_perf_bias \
		${D}${sbindir}
	install -d ${D}${systemd_unitdir}/system \
		${D}${sysconfdir}/systemd/system/multi-user.target.wants
	install -m 0644 ${WORKDIR}/energy_perf_bias.service \
		${D}${systemd_unitdir}/system
	ln -sf ${systemd_unitdir}/system/energy_perf_bias.service \
		${D}${sysconfdir}/systemd/system/multi-user.target.wants/energy_perf_bias.service

	# Replace systemd-journal-upload.service 
	install -m 0644 ${WORKDIR}/systemd-journal-upload.service \
		${D}${systemd_unitdir}/system
}
