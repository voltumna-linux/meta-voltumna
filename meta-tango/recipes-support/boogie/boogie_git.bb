SUMMARY = "Boogie is a terminal based Tango control system browser that takes inspiration from the standard tool Jive."
HOMEPAGE = "https://gitlab.com/nurbldoff/boogie/"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE.txt;md5=84dcc94da3adb52b53ae4fa38fe49e5d"

inherit python_setuptools_build_meta

SRCREV = "3ebfd655bdf5915933ef6259d79b46d1723dd4be"
SRC_URI = "git://gitlab.com/nurbldoff/boogie.git;protocol=https;branch=main"

DEPENDS += "python3-setuptools-scm-native"

RDEPENDS:${PN} += "\
    ${PYTHON_PN}-textual \
    ${PYTHON_PN}-dateutil \
    ${PYTHON_PN}-platformdirs \
    ${PYTHON_PN}-rich \
    ${PYTHON_PN}-typing-extensions \
    ${PYTHON_PN}-markdown \
    ${PYTHON_PN}-markdown-it \
    ${PYTHON_PN}-mdurl \
    "

BBCLASSEXTEND = "nativesdk"
