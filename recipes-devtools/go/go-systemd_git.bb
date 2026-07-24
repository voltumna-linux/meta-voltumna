DESCRIPTION = "Go bindings to systemd socket activation, journal, D-Bus, and unit files"
HOMEPAGE = "https://github.com/coreos/go-systemd"
SECTION = "devel/go"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=19cbd64715b51267a47bf3750cc6a8a5"

SRCNAME = "systemd"

PKG_NAME = "github.com/coreos/go-${SRCNAME}/v22"
SRC_URI = "git://github.com/coreos/go-${SRCNAME}.git;branch=main;protocol=https"

SRCREV = "4dc4ee60b8394d431f19a3c599040ef758884a27"
PV = "22.7.0+git"

RDEPENDS:${PN} += "bash"

inherit meta-virt-depreciated-warning

do_install() {
	install -d ${D}${prefix}/local/go/src/${PKG_NAME}
	cp -r ${S}/* ${D}${prefix}/local/go/src/${PKG_NAME}/
}

SYSROOT_PREPROCESS_FUNCS += "go_systemd_sysroot_preprocess"

go_systemd_sysroot_preprocess () {
    install -d ${SYSROOT_DESTDIR}${prefix}/local/go/src/${PKG_NAME}
    cp -r ${D}${prefix}/local/go/src/${PKG_NAME} ${SYSROOT_DESTDIR}${prefix}/local/go/src/$(dirname ${PKG_NAME})
}

FILES:${PN} += "${prefix}/local/go/src/${PKG_NAME}/*"
