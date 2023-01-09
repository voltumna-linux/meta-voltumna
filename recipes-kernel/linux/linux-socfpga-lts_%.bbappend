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
	\
	file://uio.cfg \
	file://fpgamgr-debug.cfg \
	file://0001-Revert-bpf-Introduce-MEM_RDONLY-flag.patch \
	file://0002-Revert-bpf-Replace-PTR_TO_XXX_OR_NULL-with-PTR_TO_XX.patch \
	file://0003-Revert-bpf-Introduce-composable-reg-ret-and-arg-type.patch \
	"

KERNEL_FEATURES:remove = " features/security/security.scc"

