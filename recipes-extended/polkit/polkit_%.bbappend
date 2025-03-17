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
        install -m 0644 ${WORKDIR}/00-log-access.rules ${D}${datadir}/polkit-1/rules.d
}
