FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

KERNEL_DEVICETREE:remove:armv7a = " \
AM335X-PRU-UIO-00A0.dtbo \
BB-ADC-00A0.dtbo \
BB-BBBW-WL1835-00A0.dtbo \
BB-BBGG-WL1835-00A0.dtbo \
BB-BBGW-WL1835-00A0.dtbo \
BB-BONE-4D5R-01-00A1.dtbo \
BB-BONE-eMMC1-01-00A0.dtbo \
BB-BONE-LCD4-01-00A1.dtbo \
BB-BONE-NH7C-01-A0.dtbo \
BB-CAPE-DISP-CT4-00A0.dtbo \
BB-HDMI-TDA998x-00A0.dtbo \
BB-I2C1-MCP7940X-00A0.dtbo \
BB-I2C1-RTC-DS3231.dtbo \
BB-I2C1-RTC-PCF8563.dtbo \
BB-I2C2-BME680.dtbo \
BB-I2C2-MPU6050.dtbo \
BB-LCD-ADAFRUIT-24-SPI1-00A0.dtbo \
BB-NHDMI-TDA998x-00A0.dtbo \
BBORG_COMMS-00A2.dtbo \
BBORG_FAN-A000.dtbo \
BBORG_RELAY-00A2.dtbo \
BB-SPIDEV0-00A0.dtbo \
BB-SPIDEV1-00A0.dtbo \
BB-UART1-00A0.dtbo \
BB-UART2-00A0.dtbo \
BB-UART4-00A0.dtbo \
BB-W1-P9.12-00A0.dtbo \
BONE-ADC.dtbo \
M-BB-BBG-00A0.dtbo \
M-BB-BBGG-00A0.dtbo \
PB-MIKROBUS-0.dtbo \
PB-MIKROBUS-1.dtbo \
"

# 6.6.32 version for 32-bit
SRCREV:armv7a = "3202dbcd519061bd24e1fa30316dd888b7e31bb0"
PV:armv7a = "6.6.32+git"
BRANCH:armv7a = "v6.6.32-ti-arm32-r6"

# 6.6.32 version for 64-bit
SRCREV:aarch64 = "0feca8b61e0fe5efa5646373450fbe86468b5857"
PV:aarch64 = "6.6.32+git"
BRANCH:aarch64 = "v6.6.32-ti-arm64-r10"

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
        file://vlan.cfg \
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
	${WORKDIR}/disable_ipv6.cfg \
	${WORKDIR}/serial_console.cfg \
	${WORKDIR}/static_usb_support.cfg \
	"

KERNEL_FEATURES:remove = " features/security/security.scc"

RDEPENDS:${KERNEL_PACKAGE_NAME}-base:remove:ti33x = "prueth-fw pruhsr-fw pruprp-fw"
KERNEL_DTBDEST = "${KERNEL_IMAGEDEST}"
