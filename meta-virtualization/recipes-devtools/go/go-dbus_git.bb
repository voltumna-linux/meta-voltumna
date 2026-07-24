DESCRIPTION = "Native Go bindings for D-Bus"
HOMEPAGE = "https://github.com/godbus/dbus"
SECTION = "devel/go"
LICENSE = "BSD-2-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=09042bd5c6c96a2b9e45ddf1bc517eed"

SRCNAME = "dbus"

PKG_NAME = "github.com/godbus/${SRCNAME}/v5"
SRC_URI = "git://github.com/godbus/${SRCNAME}.git;branch=master;protocol=https"

SRCREV = "a8ac15ba63645f02ffd57f4b443203279ab40b30"
PV = "5.2.2+git"

inherit meta-virt-depreciated-warning

do_install() {
	install -d ${D}${prefix}/local/go/src/${PKG_NAME}
	cp -r ${S}/* ${D}${prefix}/local/go/src/${PKG_NAME}/
}

SYSROOT_PREPROCESS_FUNCS += "go_dbus_sysroot_preprocess"

go_dbus_sysroot_preprocess () {
    install -d ${SYSROOT_DESTDIR}${prefix}/local/go/src/${PKG_NAME}
    cp -r ${D}${prefix}/local/go/src/${PKG_NAME} ${SYSROOT_DESTDIR}${prefix}/local/go/src/$(dirname ${PKG_NAME})
}

FILES:${PN} += "${prefix}/local/go/src/${PKG_NAME}/*"
