GRUB_BUILDIN:append = " reboot echo net efinet tftp"

PROVIDES += "virtual/bootloader"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://0001-Disable-bmi-as-well-when-SSE-and-mfpmath-sse-are-disabled.patch \
	"
