FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

#	file://use_the_right_compatible_string.patch \
#

SRCREV = "495c4b3595bb150b7a8320c89501ae7b33576898"

SRC_URI_append += " \
	file://fpgamgr-debug.cfg \
	file://initrd.cfg \
	file://disable_ip_nfsroot.cfg \
	file://noswap.cfg \
	file://optimization.cfg \
	file://strict_devmem.cfg \
	file://systemd.cfg \
	file://disable_ptp.cfg \
	file://remove_martian_source_warning.cfg \
	file://enable_ebpf_xpd.cfg \
	file://uio.cfg \
	"
