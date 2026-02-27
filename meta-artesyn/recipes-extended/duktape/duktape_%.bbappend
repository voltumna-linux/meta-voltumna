FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://0001-Disable-packed-tval-NaN-boxing-on-PowerPC-SPE-target.patch \
	"
