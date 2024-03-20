FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

LINUX_VERSION_PREFIX = "elettra-"
KERNEL_REPO = "git://gitlab.elettra.eu/intel_socfpga/linux-socfpga.git"
SRCREV = "dccc6abe878f2e787d081027a84b8a79606e8d2e"
LINUX_VERSION = "5.15.60"
PREFERRED_VERSION_linux-socfpga-lts = "5.15"

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
	"

KERNEL_FEATURES:remove = " features/security/security.scc"

