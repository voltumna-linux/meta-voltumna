DESCRIPTION = "Trusted Firmware-A tests(aka TFTF)"
LICENSE = "BSD-3-Clause & NCSA"

LIC_FILES_CHKSUM += "file://docs/license.rst;md5=6175cc0aa2e63b6d21a32aa0ee7d1b4a"

inherit deploy

COMPATIBLE_MACHINE ?= "invalid"

SRC_URI = "git://git.trustedfirmware.org/TF-A/tf-a-tests.git;protocol=https;branch=master"
# post v2.6 snapshot
SRCREV ?= "af5a517ae9f295455122109100fe5d55668e8eaf"
PV .= "+git${SRCPV}"

DEPENDS += "optee-os"

EXTRA_OEMAKE += "USE_NVM=0"
EXTRA_OEMAKE += "SHELL_COLOR=1"
EXTRA_OEMAKE += "DEBUG=1"

# Platform must be set for each machine
TFA_PLATFORM ?= "invalid"

EXTRA_OEMAKE += "ARCH=aarch64"
EXTRA_OEMAKE += "LOG_LEVEL=50"

S = "${WORKDIR}/git"
B = "${WORKDIR}/build"

# Add platform parameter
EXTRA_OEMAKE += "BUILD_BASE=${B} PLAT=${TFA_PLATFORM}"

# Requires CROSS_COMPILE set by hand as there is no configure script
export CROSS_COMPILE="${TARGET_PREFIX}"

do_compile() {
    oe_runmake -C ${S} tftf
}

do_compile[cleandirs] = "${B}"

FILES:${PN} = "/firmware/tftf.bin"
SYSROOT_DIRS += "/firmware"

do_install() {
    install -d -m 755 ${D}/firmware
    install -m 0644 ${B}/${TFA_PLATFORM}/debug/tftf.bin ${D}/firmware/tftf.bin
}

do_deploy() {
    cp -rf ${D}/firmware/* ${DEPLOYDIR}/
}
addtask deploy after do_install
