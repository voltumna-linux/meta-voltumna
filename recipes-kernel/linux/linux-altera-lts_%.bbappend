FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append += " \
	file://log.cfg \
	file://zram.cfg \
	file://initrd.cfg \
	file://disable_ip_nfsroot.cfg \
	file://optimization.cfg \
	file://strict_devmem.cfg \
	file://systemd.cfg \
	file://disable_ptp.cfg \
	file://remove_martian_source_warning.cfg \
	file://enable_ebpf_xpd.cfg \
	\
	file://uio.cfg \
	file://fpgamgr-debug.cfg \
	"

KERNEL_FEATURES_remove = " features/security/security.scc"

