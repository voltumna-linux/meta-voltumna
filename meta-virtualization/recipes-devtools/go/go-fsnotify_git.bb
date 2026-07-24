DESCRIPTION = "A golang registry for global request variables."
HOMEPAGE = "https://github.com/go-fsnotify/fsnotify"
SECTION = "devel/go"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=8bae8b116e2cfd723492b02d9a212fe2"

SRCNAME = "fsnotify"

PKG_NAME = "github.com/fsnotify/${SRCNAME}"
SRC_URI = "git://${PKG_NAME}.git;branch=main;protocol=https"

SRCREV = "ae0e7923765f64fb8061396db7edebb558cf6093"
PV = "1.9.0+git"

inherit meta-virt-depreciated-warning

do_install() {
	install -d ${D}${prefix}/local/go/src/${PKG_NAME}
	cp -r ${S}/* ${D}${prefix}/local/go/src/${PKG_NAME}/
}

SYSROOT_PREPROCESS_FUNCS += "go_fsnotify_sysroot_preprocess"

go_fsnotify_sysroot_preprocess () {
    install -d ${SYSROOT_DESTDIR}${prefix}/local/go/src/${PKG_NAME}
    cp -r ${D}${prefix}/local/go/src/${PKG_NAME} ${SYSROOT_DESTDIR}${prefix}/local/go/src/$(dirname ${PKG_NAME})
}

FILES:${PN} += "${prefix}/local/go/src/${PKG_NAME}/*"
