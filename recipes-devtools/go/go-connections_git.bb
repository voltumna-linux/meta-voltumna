DESCRIPTION = "Utility package to work with network connections"
HOMEPAGE = "https://github.com/docker/connections"
SECTION = "devel/go"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://src/${PKG_NAME}/LICENSE;md5=04424bc6f5a5be60691b9824d65c2ad8"

SRCNAME = "go-connections"

PKG_NAME = "github.com/docker/${SRCNAME}"
SRC_URI = "git://${PKG_NAME}.git;destsuffix=${BB_GIT_DEFAULT_DESTSUFFIX}/src/${PKG_NAME};branch=main;protocol=https"

SRCREV = "42faf792bde28c414a060127d6351769408a675f"
PV = "0.6.0+git"

inherit meta-virt-depreciated-warning

# NO-OP the do compile rule because this recipe is source only.
do_compile() {
}

do_install() {
	install -d ${D}${prefix}/local/go/src/${PKG_NAME}
	for j in $(cd ${S} && find src/${PKG_NAME} -name "*.go"); do
	    if [ ! -d ${D}${prefix}/local/go/$(dirname $j) ]; then
	        mkdir -p ${D}${prefix}/local/go/$(dirname $j)
	    fi
	    cp $j ${D}${prefix}/local/go/$j
	done
	cp -r ${S}/src/${PKG_NAME}/LICENSE ${D}${prefix}/local/go/src/${PKG_NAME}/
}

SYSROOT_PREPROCESS_FUNCS += "go_connections_sysroot_preprocess"

go_connections_sysroot_preprocess () {
    install -d ${SYSROOT_DESTDIR}${prefix}/local/go/src/${PKG_NAME}
    cp -r ${D}${prefix}/local/go/src/${PKG_NAME} ${SYSROOT_DESTDIR}${prefix}/local/go/src/$(dirname ${PKG_NAME})
}

FILES:${PN} += "${prefix}/local/go/src/${PKG_NAME}/*"
