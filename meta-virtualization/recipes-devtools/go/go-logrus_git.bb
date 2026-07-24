DESCRIPTION = "A golang registry for global request variables."
HOMEPAGE = "https://github.com/Sirupsen/logrus"
SECTION = "devel/go"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=8dadfef729c08ec4e631c4f6fc5d43a0"

SRCNAME = "logrus"

PKG_NAME = "github.com/sirupsen/${SRCNAME}"
SRC_URI = "git://${PKG_NAME};branch=master;protocol=https"

SRCREV = "a29884b9be3dc22c18338c0fe5a51d23e69731e4"
PV = "1.9.4+git"

inherit meta-virt-depreciated-warning

do_install() {
	install -d ${D}${prefix}/local/go/src/${PKG_NAME}
	cp -r ${S}/* ${D}${prefix}/local/go/src/${PKG_NAME}/
	rm -rf ${D}${prefix}/local/go/src/${PKG_NAME}/travis
}

SYSROOT_PREPROCESS_FUNCS += "go_logrus_sysroot_preprocess"

go_logrus_sysroot_preprocess () {
    install -d ${SYSROOT_DESTDIR}${prefix}/local/go/src/${PKG_NAME}
    cp -r ${D}${prefix}/local/go/src/${PKG_NAME} ${SYSROOT_DESTDIR}${prefix}/local/go/src/$(dirname ${PKG_NAME})
}

FILES:${PN} += "${prefix}/local/go/src/${PKG_NAME}/*"
