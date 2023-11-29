FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append += " \
	file://00-log-access.rules \
	"

do_install_append() {
	# Set the right permission
	chmod 755 ${D}${sysconfdir}/polkit-1/rules.d ${D}${datadir}/polkit-1/rules.d

	# Add additional rules files
        install -m 0644 ${WORKDIR}/00-log-access.rules ${D}${datadir}/polkit-1/rules.d
}

GTKDOC_ENABLED = "False"
