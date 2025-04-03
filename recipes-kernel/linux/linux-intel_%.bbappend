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
        file://disable_ipv6.cfg  \
	\
	file://numa.cfg \
	file://dpdk.cfg \
	file://vfio.cfg \
	file://nvram.cfg \
	file://hpet.cfg \
	file://vtd.cfg \
	file://serial_console.cfg \
	file://static_intel_drivers.cfg \
	"

KERNEL_FEATURES_remove = " features/security/security.scc"

# COMPATIBLE_MACHINE_append = "|nu93-2930"
