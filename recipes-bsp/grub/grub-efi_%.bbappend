GRUB_BUILDIN:append = " reboot echo net efinet tftp"

PROVIDES += "virtual/bootloader"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

PACKAGE_ARCH = "${MACHINE_ARCH}"

SRC_URI:append = " \
	file://0001-Disable-bmi-as-well-when-SSE-and-mfpmath-sse-are-disabled.patch \
	"
