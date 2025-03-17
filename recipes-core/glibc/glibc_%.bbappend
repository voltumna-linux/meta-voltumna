FILESEXTRAPATHS:prepend := "${THISDIR}/glibc:"

SRC_URI:append = " \
	file://0001-elf-Silence-GCC-11-12-false-positive-warning.patch \
	"

PACKAGES:prepend           = "${PN}-getent "
FILES:${PN}-getent         = "${bindir}/getent"
SUMMARY:${PN}-getent       = "Print entries from Name Service Switch libraries"
DESCRIPTION:${PN}-getent   = "Prints entries from Name Service Switch libraries."
RDEPENDS:${PN}-utils      += "${PN}-getent"
