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
	file://disable_gpiolib.cfg \
	\
	file://uio.cfg \
	file://fpgamgr-debug.cfg \
	file://0001-Revert-bpf-Introduce-MEM_RDONLY-flag.patch \
	file://0002-Revert-bpf-Replace-PTR_TO_XXX_OR_NULL-with-PTR_TO_XX.patch \
	file://0003-Revert-bpf-Introduce-composable-reg-ret-and-arg-type.patch \
	file://0001-added-support-to-dinet-board.patch \
	file://0002-added-support-to-DAQ-board.patch \
	file://0003-changed-adt-address-enabled-driver-in-defconfig.patch \
	file://0004-enabled-second-i2c-routed-through-FPGA-pins.patch \
	file://0005-corrected-i2c-address-of-fan-controller.patch \
	file://0006-soft-gpio-working.patch \
	file://0007-preliminary-tests-with-spi.patch \
	file://0008-added-clocks-in-device-tree.patch \
	file://0009-enabled-regulators-always-on-and-present-at-boot.patch \
	file://0010-cosmetic-changes.patch \
	"

KERNEL_FEATURES:remove = " features/security/security.scc"

