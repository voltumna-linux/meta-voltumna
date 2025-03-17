FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

#SRC_URI:append = " \
#	file://thermald.service \
#	"
#
#do_install:append() {
#	install -m 0644 ${WORKDIR}/thermald.service \
#		${D}${systemd_unitdir}/system
#}
