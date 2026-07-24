DESCRIPTION = "A small package for building command line apps in Go"
HOMEPAGE = "https://github.com/codegangsta/cli"
SECTION = "devel/go"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=51992c80b05795f59c22028d39f9b74c"

SRCNAME = "cli"

PKG_NAME = "github.com/urfave/${SRCNAME}/v2"
SRC_URI = "git://github.com/urfave/${SRCNAME}.git;branch=v2-maint;protocol=https"

SRCREV = "19b951ab78929023a9a670722b26ffb1d67c733a"
PV = "2.27.7+git"

inherit meta-virt-depreciated-warning

# Source-only package, no compilation needed
do_compile[noexec] = "1"
do_configure[noexec] = "1"

do_install() {
	install -d ${D}${prefix}/local/go/src/${PKG_NAME}
	cp -r ${S}/* ${D}${prefix}/local/go/src/${PKG_NAME}/
}

SYSROOT_PREPROCESS_FUNCS += "go_cli_sysroot_preprocess"

go_cli_sysroot_preprocess () {
    install -d ${SYSROOT_DESTDIR}${prefix}/local/go/src/${PKG_NAME}
    cp -r ${D}${prefix}/local/go/src/${PKG_NAME} ${SYSROOT_DESTDIR}${prefix}/local/go/src/$(dirname ${PKG_NAME})
}

FILES:${PN} += "${prefix}/local/go/src/${PKG_NAME}/*"
