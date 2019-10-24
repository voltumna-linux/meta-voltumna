FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append += " \
	file://serial_console.cfg \
	file://static_usb_support.cfg \
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

KERNEL_CONFIG_FRAGMENTS_append += " \
	${WORKDIR}/serial_console.cfg \
	${WORKDIR}/static_usb_support.cfg \
	${WORKDIR}/initrd.cfg \
	${WORKDIR}/disable_ip_nfsroot.cfg \
	${WORKDIR}/noswap.cfg \
	${WORKDIR}/optimization.cfg \
	${WORKDIR}/strict_devmem.cfg \
	${WORKDIR}/systemd.cfg \
	${WORKDIR}/disable_ptp.cfg \
	${WORKDIR}/remove_martian_source_warning.cfg \
	${WORKDIR}/enable_ebpf_xpd.cfg \
	"
