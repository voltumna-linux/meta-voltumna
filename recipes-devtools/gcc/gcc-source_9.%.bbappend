FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://0001-Revert-Delete-powerpcspe.patch \
	file://0001-Fix-hard_regno_call_part_clobbered-signature.patch \
	"
