FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
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
	file://disable_lttng.cfg \
	file://disable_ipv6.cfg \
	\
	file://vme.cfg \
	"

SRC_URI:append:mvme5100 = " \
	file://cmdline.cfg \
	"

SRC_URI:append:mvme7100 = " \
	file://cmdline.cfg \
	"

KERNEL_FEATURES:remove = " features/security/security.scc"
