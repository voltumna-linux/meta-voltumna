FILESEXTRAPATHS:prepend := "${THISDIR}/glibc:"

PACKAGES:prepend           = "${PN}-getent "
FILES:${PN}-getent         = "${bindir}/getent"
SUMMARY:${PN}-getent       = "Print entries from Name Service Switch libraries"
DESCRIPTION:${PN}-getent   = "Prints entries from Name Service Switch libraries."
RDEPENDS:${PN}-utils      += "${PN}-getent"
