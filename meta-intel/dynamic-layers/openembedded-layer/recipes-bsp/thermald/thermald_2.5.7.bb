SUMMARY = "Linux thermal daemon"

DESCRIPTION = "Thermal Daemon is a Linux daemon used to prevent the \
overheating of platforms. This daemon monitors temperature and applies \
compensation using available cooling methods."

HOMEPAGE = "https://github.com/01org/thermal_daemon"

DEPENDS = "dbus dbus-glib dbus-glib-native libxml2 glib-2.0 glib-2.0-native upower libevdev"
DEPENDS += "autoconf-archive-native"

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=ea8831610e926e2e469075b52bf08848"

SRC_URI = "git://github.com/intel/thermal_daemon/;branch=master;protocol=https \
           file://0001-Makefile-Fix-build-Issue.patch \
           "

SRCREV = "ea8b773f76641a7a49d6584669e17371c22ad03e"
S = "${WORKDIR}/git"

inherit pkgconfig autotools systemd gtk-doc

# gtkdocsize runs before autotools do_configure and it copies gtk-doc.m4 and fails
# to copy becuase there is no m4 dir yet.
do_configure:prepend () {
	mkdir -p ${S}/m4
}

EXTRA_OECONF = " \
                 --with-systemdsystemunitdir=${systemd_system_unitdir} \
                 "

FILES:${PN} += "${datadir}/dbus-1"

SYSTEMD_SERVICE:${PN} = "thermald.service"

COMPATIBLE_HOST = '(i.86|x86_64).*-linux'

CONFFILES:${PN} = " \
                   ${sysconfdir}/thermald/thermal-conf.xml \
                   ${sysconfdir}/thermald/thermal-cpu-cdev-order.xml \
                  "

UPSTREAM_CHECK_URI = "https://github.com/01org/thermal_daemon/releases"
