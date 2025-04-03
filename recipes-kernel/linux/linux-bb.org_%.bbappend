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
	file://serial_console.cfg \
	file://static_usb_support.cfg \
	"

SRC_URI[sha256sum] = "f282d4d33ee9f3d679dd1e6c8290236b395ddda051346bb10e71e50c6bab2e7e"

KERNEL_CONFIG_FRAGMENTS:append = " \
	${WORKDIR}/log.cfg \
	${WORKDIR}/zram.cfg \
	${WORKDIR}/initrd.cfg \
	${WORKDIR}/disable_ip_nfsroot.cfg \
	${WORKDIR}/optimization.cfg \
	${WORKDIR}/strict_devmem.cfg \
	${WORKDIR}/systemd.cfg \
	${WORKDIR}/disable_ptp.cfg \
	${WORKDIR}/remove_martian_source_warning.cfg \
	${WORKDIR}/enable_ebpf_xpd.cfg \
	${WORKDIR}/disable_lttng.cfg \
	${WORKDIR}/serial_console.cfg \
	${WORKDIR}/static_usb_support.cfg \
	"

KERNEL_FEATURES:remove = " features/security/security.scc"

RDEPENDS:${KERNEL_PACKAGE_NAME}-base:remove:ti33x = " prueth-fw pruhsr-fw pruprp-fw"
KERNEL_DTBDEST = "${KERNEL_IMAGEDEST}"
