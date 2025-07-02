FILESEXTRAPATHS:prepend := "${THISDIR}/linux-yocto-5.15:"

KMACHINE = "common-pc-64"
SRCREV_meta = "1128d7bcdcde490d4f35cc00c97f5410bb240d99"
LINUX_VERSION = "5.15.68"
LINUX_VERSION_EXTENSION = "-amd-${LINUX_KERNEL_TYPE}"

COMPATIBLE_MACHINE = "${MACHINE}"

INC_PR := "r1"

SRC_URI:append = " \
      file://amdx86.cfg \
      file://amdx86-user-config.cfg \
      file://amdx86-extra-config.cfg \
      file://amd-xgbe.cfg \
      file://kvm.cfg \
      file://afalg.cfg \
      file://amdx86-standard-only.cfg \
      file://logo.cfg \
      file://console.cfg \
      file://sound.cfg \
      file://hid.cfg \
      file://usb-serial.cfg \
      file://spi-driver.cfg \
      file://wdt-driver.cfg \
      file://wifi-drivers.cfg \
      ${@bb.utils.contains('MACHINE_FEATURES', 'ccp', 'file://amd-ccp.cfg', '', d)} \
      ${@bb.utils.contains('MACHINE_FEATURES', 'screen', 'file://enable-graphics.cfg', 'file://disable-graphics.cfg', d)} \
      ${@bb.utils.contains('DISTRO_FEATURES', 'bluetooth', 'file://enable-bluetooth.cfg', 'file://disable-bluetooth.cfg', d)} \
      ${@bb.utils.contains('DISTRO', 'poky-amd', 'file://enable-kgdb.cfg', 'file://disable-kgdb.cfg', d)} \
      ${@bb.utils.contains('EXTRA_IMAGE_FEATURES', 'amd-feature-networking', 'file://dpdk.cfg', '', d)} \
      file://fragment.cfg \
      file://upstream.scc \
      file://core.scc \
      file://spi.scc \
      file://smbus.scc \
      file://ucsi.scc \
      file://wdt.scc \
      file://usb.scc \
      file://net-phy.scc \
      file://xgbe.scc \
    "
