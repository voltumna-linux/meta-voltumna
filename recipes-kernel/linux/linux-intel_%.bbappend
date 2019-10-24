FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append += " \
	file://serial_console.cfg \
	file://static_intel_drivers.cfg \
	file://initrd.cfg \
	file://disable_ip_nfsroot.cfg \
	file://noswap.cfg \
	file://optimization.cfg \
	file://strict_devmem.cfg \
	file://systemd.cfg \
	file://disable_ptp.cfg \
	file://remove_martian_source_warning.cfg \
	file://enable_ebpf_xpd.cfg \
	"

# COMPATIBLE_MACHINE_append = "|nu93-2930"
