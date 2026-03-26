FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

KERNEL_DEVICETREE:remove:armv7a = " \
    ti/omap/AM335X-PRU-UIO-00A0.dtbo \
    ti/omap/BB-ADC-00A0.dtbo \
    ti/omap/BB-BBBW-WL1835-00A0.dtbo \
    ti/omap/BB-BBGG-WL1835-00A0.dtbo \
    ti/omap/BB-BBGW-WL1835-00A0.dtbo \
    ti/omap/BB-BONE-4D5R-01-00A1.dtbo \
    ti/omap/BB-BONE-eMMC1-01-00A0.dtbo \
    ti/omap/BB-BONE-LCD4-01-00A1.dtbo \
    ti/omap/BB-BONE-NH7C-01-A0.dtbo \
    ti/omap/BB-CAPE-DISP-CT4-00A0.dtbo \
    ti/omap/BB-HDMI-TDA998x-00A0.dtbo \
    ti/omap/BB-I2C1-MCP7940X-00A0.dtbo \
    ti/omap/BB-I2C1-RTC-DS3231.dtbo \
    ti/omap/BB-I2C1-RTC-PCF8563.dtbo \
    ti/omap/BB-I2C2-BME680.dtbo \
    ti/omap/BB-I2C2-MPU6050.dtbo \
    ti/omap/BB-LCD-ADAFRUIT-24-SPI1-00A0.dtbo \
    ti/omap/BB-NHDMI-TDA998x-00A0.dtbo \
    ti/omap/BBORG_COMMS-00A2.dtbo \
    ti/omap/BBORG_FAN-A000.dtbo \
    ti/omap/BBORG_RELAY-00A2.dtbo \
    ti/omap/BB-SPIDEV0-00A0.dtbo \
    ti/omap/BB-SPIDEV1-00A0.dtbo \
    ti/omap/BB-UART1-00A0.dtbo \
    ti/omap/BB-UART2-00A0.dtbo \
    ti/omap/BB-UART4-00A0.dtbo \
    ti/omap/BB-W1-P9.12-00A0.dtbo \
    ti/omap/BONE-ADC.dtbo \
    ti/omap/M-BB-BBG-00A0.dtbo \
    ti/omap/M-BB-BBGG-00A0.dtbo \
    ti/omap/PB-MIKROBUS-0.dtbo \
    ti/omap/PB-MIKROBUS-1.dtbo \
"

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

do_deploy:append:beaglebone() {
    mv ${D}/${KERNEL_DTBDEST}/ti/omap/* ${D}/${KERNEL_DTBDEST}
    rm -fr ${D}/${KERNEL_DTBDEST}/ti/
}
