SUMMARY = "Board Firmware binaries for N1SDP"
SECTION = "firmware"

LICENSE = "STM-SLA0044-Rev5"
LIC_FILES_CHKSUM = "file://LICENSES/STM.TXT;md5=4b8dab81d0bfc0a5f63c9a983402705b"

inherit deploy

INHIBIT_DEFAULT_DEPS = "1"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_MACHINE = "n1sdp"

SRC_URI = "git://git.linaro.org/landing-teams/working/arm/n1sdp-board-firmware.git;protocol=https;branch=master"

SRCREV  = "9a095cbdf8ef59a7433e2769e4e2e92782b68c50"

S = "${WORKDIR}/git"

INSTALL_DIR = "/n1sdp-board-firmware_source"

do_install() {
    rm -rf ${S}/SOFTWARE
    install -d ${D}${INSTALL_DIR}
    cp -Rp --no-preserve=ownership ${S}/* ${D}${INSTALL_DIR}
}

FILES:${PN} = "${INSTALL_DIR}"
SYSROOT_DIRS += "${INSTALL_DIR}"

do_deploy() {
    install -d ${DEPLOYDIR}${INSTALL_DIR}
    cp -Rp --no-preserve=ownership ${S}/* ${DEPLOYDIR}${INSTALL_DIR}
}
addtask deploy after do_install before do_build
