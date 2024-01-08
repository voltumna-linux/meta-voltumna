FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

#SRC_URI_append = " \
#	file://thermald.service \
#	"
#
#do_install_append() {
#	install -m 0644 ${WORKDIR}/thermald.service \
#		${D}${systemd_unitdir}/system
#}
