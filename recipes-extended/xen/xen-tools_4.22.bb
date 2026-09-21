SRCREV = "b8fe9e33743c7a387b67fee9d288dcb5c49f3813"

XEN_REL = "4.22.0"
XEN_BRANCH = "stable-4.22"

SRC_URI = " \
    git://xenbits.xen.org/xen.git;branch=${XEN_BRANCH} \
    file://0001-python-pygrub-pass-DISTUTILS-xen-4.19.patch \
    file://0001-libxl_nocpuid-fix-build-error.patch \
    file://0001-tests-vpci-drop-explicit-g-use-4.22.patch \
    "

LIC_FILES_CHKSUM ?= "file://COPYING;md5=d1a1e216f80b6d8da95fec897d0dbec9"

PV = "${XEN_REL}+stable"

DEFAULT_PREFERENCE ??= "-1"

require xen.inc
require xen-tools.inc
