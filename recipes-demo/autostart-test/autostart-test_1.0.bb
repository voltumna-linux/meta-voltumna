SUMMARY = "Simple test service for container autostart verification"
DESCRIPTION = "A shell script that runs continuously and logs timestamps, \
useful for verifying container autostart functionality."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://autostart-test.sh"

S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/autostart-test.sh ${D}${bindir}/autostart-test
}

RDEPENDS:${PN} = "busybox"
