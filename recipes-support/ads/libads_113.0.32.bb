DESCRIPTION = "Beckhoff protocol to communicate with TwinCAT devices."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=b20289b0f8d3f1fde00abc1e1dba20ab"

SRC_URI = " \
    git://github.com/Beckhoff/ADS.git;protocol=https;branch=master \
    file://0001-AdsLib-Add-extern-C-to-allow-shared-library-exports.patch \
    file://0002-meson-build-a-shared-library-for-the-standalone-vers.patch \
    file://add_soname_version.patch \
    "
SRCREV = "b64332b6a63be3041619c717c2aa3e1922ed86b1"

S = "${WORKDIR}/git"

PACKAGES =+ "${PN}-bin"
do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/adstool ${D}${bindir}
}

inherit meson

BBCLASSEXTEND = "nativesdk"
