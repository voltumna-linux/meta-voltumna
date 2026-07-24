SRCREV ?= "1c72306b1f0b4dc533954f678361044f8083dccc"

XEN_REL ?= "4.21.0"
XEN_BRANCH ?= "stable-4.21"

SRC_URI = " \
    git://xenbits.xen.org/xen.git;branch=${XEN_BRANCH} \
    file://0001-menuconfig-mconf-cfg-Allow-specification-of-ncurses-location.patch \
    file://0001-libxl_nocpuid-fix-build-error.patch \
    file://0001-ARM-Drop-ThumbEE-support.patch \
    "

LIC_FILES_CHKSUM ?= "file://COPYING;md5=d1a1e216f80b6d8da95fec897d0dbec9"

PV = "${XEN_REL}+stable"

DEFAULT_PREFERENCE ??= "-1"

require xen.inc
require xen-hypervisor.inc
