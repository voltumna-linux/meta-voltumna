GRUB_BUILDIN_append = " reboot echo net efinet tftp"

FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append = " \
	file://0001-Disable-bmi-as-well-when-SSE-and-mfpmath-sse-are-disabled.patch \
	"
