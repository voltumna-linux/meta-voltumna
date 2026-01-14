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
	file://vtd-amd.cfg \
	file://serial_console.cfg \
	file://ipmi.cfg \
	file://osnoise.cfg \
	\
	file://resctrl.cfg \
        file://amd-extra.cfg \
        file://fix-build-error.patch \
	"

SRC_URI:append:kvm = " \
	file://virtualization.cfg \
	"

KERNEL_FEATURES:append = " features/perf/perf.scc"
KERNEL_FEATURES:remove = " features/security/security.scc"
