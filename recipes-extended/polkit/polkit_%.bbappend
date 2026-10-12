FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://00-log-access.rules \
	"

# On Beaglebone polkit build failed due: 
# make[3]: *** No rule to make target 'overview.xml', needed by 'html-build.stamp'.  Stop.
EXTRA_OECONF:append = ' \
	--disable-gtk-doc  \
	'

do_install:append() {
	# Set the right permission
	chmod 755 ${D}${sysconfdir}/polkit-1/rules.d ${D}${datadir}/polkit-1/rules.d

	# Add additional rules files
        install -m 0644 ${UNPACKDIR}/00-log-access.rules ${D}${datadir}/polkit-1/rules.d
}

# polkit-agent-helper.socket and polkit-agent-helper@.service are packaged
# in ${PN}-service (FILES:${PN}-service grabs ${systemd_system_unitdir}),
# not in ${PN}. Upstream SYSTEMD_SERVICE:${PN} entry therefore makes the
# ${PN} %post run "systemctl enable polkit-agent-helper.socket" without the
# unit file in the rootfs -> do_rootfs failure. Move the socket handling to
# the package that actually ships the units.
SYSTEMD_SERVICE:${PN}:remove = "polkit-agent-helper.socket"
SYSTEMD_SERVICE:${PN}-service += "polkit-agent-helper.socket polkit-agent-helper@.service"
