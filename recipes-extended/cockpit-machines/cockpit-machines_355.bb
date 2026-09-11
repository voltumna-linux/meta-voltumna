# Copyright (C) 2024-2025 Savoir-faire Linux, Inc

SUMMARY = "Cockpit UI for virtual machines"
DESCRIPTION = "Cockpit-machines provides a user interface to manage virtual machines"

BUGTRACKER = "github.com/cockpit-project/cockpit-machines/issues"

LICENSE = "LGPL-2.1-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=4fbd65380cdd255951079008b364516c"

DEPENDS += "cockpit"

SRC_URI = "https://github.com/cockpit-project/cockpit-machines/releases/download/${PV}/cockpit-machines-${PV}.tar.xz"
SRC_URI[sha256sum] = "a99a198061e43ec0ab83ecaa95dcb492a77dcb0a459323f0546a5a08eeb3cfeb"

S = "${UNPACKDIR}/${PN}"

inherit features_check

# systemd, which cockpit is dependent, is not compatible with musl lib
COMPATIBLE_HOST:libc-musl = "null"

RDEPENDS:${PN} += "cockpit libvirt-dbus pciutils virt-manager-install"

REQUIRED_DISTRO_FEATURES = "systemd pam"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${datadir}/cockpit/machines
    cp -r ${S}/dist/* ${D}${datadir}/cockpit/machines/

    install -d ${D}${datadir}/metainfo
    install -m 0644 ${S}/org.cockpit_project.machines.metainfo.xml ${D}${datadir}/metainfo/
}

FILES:${PN} = "\
    ${datadir}/cockpit/machines/ \
    ${datadir}/metainfo/org.cockpit_project.machines.metainfo.xml \
"

SKIP_RECIPE[cockpit-machines] ?= "${@bb.utils.contains('BBFILE_COLLECTIONS', 'webserver', '', 'Depends on meta-webserver which is not included', d)}"

