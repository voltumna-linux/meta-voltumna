SUMMARY = "A simple CLI tool for packing rootfs into a single-layer OCI image"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=896c8ffa3d0539d0d980d0217269969d"
SRC_URI = "git://github.com/jirutka/sloci-image.git;branch=master;protocol=https"


DEPENDS = ""

SRCREV = "b45be2e049c5c55acb04a5edb017b793d2d9e677"
PV = "v0.1.2+git"

do_compile() { 
	:
}

do_install() {
	cd ${S}
        make PREFIX="${exec_prefix}" DESTDIR=${D} install
}

CLEANBROKEN = "1"

BBCLASSEXTEND = "native nativesdk"
