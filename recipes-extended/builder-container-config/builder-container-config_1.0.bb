SUMMARY = "Entrypoint and user configuration for Yocto builder container"
DESCRIPTION = "CROPS-style entrypoint script that creates a builder user \
    matching the /workdir mount owner, then hands off to systemd."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://builder-entry.sh"

S = "${UNPACKDIR}"
RDEPENDS:${PN} = "bash sudo shadow"

inherit allarch

do_install() {
    # Entrypoint script (CROPS-style user creation -> exec /sbin/init)
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/builder-entry.sh ${D}${bindir}/

    # Create /workdir mount point
    install -d ${D}/workdir
}

FILES:${PN} = "${bindir}/builder-entry.sh /workdir"
