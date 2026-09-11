SUMMARY = "LXCFS is a userspace filesystem created to avoid kernel limitations"
LICENSE = "LGPL-2.1-or-later"

REQUIRED_DISTRO_FEATURES ?= "systemd"
inherit meson pkgconfig systemd features_check

SRC_URI = " \
    https://linuxcontainers.org/downloads/lxcfs/lxcfs-${PV}.tar.gz \
    file://0001-meson.build-force-pid-open-send_signal-detection.patch \
"

LIC_FILES_CHKSUM = "file://COPYING;md5=29ae50a788f33f663405488bc61eecb1"
SRC_URI[sha256sum] = "89a5ac0e98cfae6aad26d00e0e977affe810865ebccd4c4cf9422f980ade5624"

DEPENDS += "fuse3 python3-jinja2-native help2man-native systemd"
RDEPENDS:${PN} += "fuse3"

FILES:${PN} += "${datadir}/lxc/config/common.conf.d/*"

# help2man doesn't work, so we disable docs
EXTRA_OEMESON += "-Dinit-script=${VIRTUAL-RUNTIME_init_manager} -Ddocs=false"

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "lxcfs.service"
