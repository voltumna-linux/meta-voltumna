SUMMARY = "Systemd service masking for container use"
DESCRIPTION = "Masks systemd services that are inappropriate inside containers \
    (udev, hwdb, serial-getty, etc.). Installed as a package so it works \
    with both single-layer and multi-layer OCI images."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit allarch

# Default services to mask in containers
# Customizable: CONTAINER_SYSTEMD_MASK:pn-container-systemd-config:append = " extra.service"
CONTAINER_SYSTEMD_MASK ?= "\
    systemd-udevd.service \
    systemd-udevd-control.socket \
    systemd-udevd-kernel.socket \
    proc-sys-fs-binfmt_misc.automount \
    sys-fs-fuse-connections.mount \
    sys-kernel-debug.mount \
    systemd-hwdb-update.service \
    serial-getty@ttyS0.service \
    dev-ttyS0.device \
    console-getty.service \
    serial-getty@.service \
"

do_install() {
    install -d ${D}${sysconfdir}/systemd/system
    for service in ${CONTAINER_SYSTEMD_MASK}; do
        ln -sf /dev/null ${D}${sysconfdir}/systemd/system/$service
    done
}
