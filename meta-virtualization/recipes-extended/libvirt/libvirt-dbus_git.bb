SUMMARY = "dBus wrapper for libvirt"
DESCRIPTION = "libvirt-dbus wraps libvirt API to provide a high-level object-oriented API better suited for dbus-based applications."
AUTHOR = "Lars Karlitski <lars@karlitski.net> Pavel Hrdina <phrdina@redhat.com> Katerina Koukiou <kkoukiou@redhat.com>"
HOMEPAGE = "https://www.libvirt.org/dbus.html"
BUGTRACKER = "https://gitlab.com/libvirt/libvirt-dbus/-/issues"
SECTION = "libs"
LICENSE = "LGPL-2.1-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=4fbd65380cdd255951079008b364516c"
CVE_PRODUCT = "libvirt-dbus"

DEPENDS += "glib-2.0 libvirt libvirt-glib python3-docutils-native"

SRC_URI = "git://gitlab.com/libvirt/libvirt-dbus.git;nobranch=1;protocol=https"

PV = "1.4.1+git"
SRCREV = "d1c49c2e3616249d1c88cd52fa0deb3e6d0e588f"

inherit meson pkgconfig

FILES:${PN} += "\
    ${datadir}/dbus-1/* \
    ${datadir}/polkit-1/* \
    ${nonarch_libdir}/sysusers.d \
"
