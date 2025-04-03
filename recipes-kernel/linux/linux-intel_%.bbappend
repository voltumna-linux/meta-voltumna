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
	file://numa.cfg \
	file://dpdk.cfg \
	file://vfio.cfg \
	file://nvram.cfg \
	file://hpet.cfg \
	file://vtd.cfg \
	file://serial_console.cfg \
	file://ipmi.cfg \
	\
	file://static_intel_drivers.cfg \
	file://0001-igb-Stop-PTP-related-workqueues-if-aren-t-necessary.patch \
	file://resctrl.cfg \
	file://0001-sched-core-Fix-arch_scale_freq_tick-on-tickless-syst.patch \
	file://0001-hugetlbfs-extend-the-definition-of-hugepages-paramet.patch \
	"

SRC_URI:append:kvm = " \
	file://virtualization.cfg \
	"

KERNEL_FEATURES:remove = " features/security/security.scc"
