SRCREV = "b8fe9e33743c7a387b67fee9d288dcb5c49f3813"

XEN_REL = "4.22.0"
XEN_BRANCH = "stable-4.22"

SRC_URI = " \
    git://xenbits.xen.org/xen.git;branch=${XEN_BRANCH} \
    file://0001-menuconfig-mconf-cfg-Allow-specification-of-ncurses-location.patch \
    file://0001-libxl_nocpuid-fix-build-error.patch \
    file://0001-efi-boot-warn-instead-of-fatal-exit-for-unverified-kernel.patch \
    file://0001-x86-hyperv-disable-hypercall-assisted-TLB-flush.patch \
    file://0001-x86-io_apic-don-t-panic-on-missing-legacy-timer-under.patch \
    file://hyperv-guest.cfg \
    "

LIC_FILES_CHKSUM ?= "file://COPYING;md5=d1a1e216f80b6d8da95fec897d0dbec9"

PV = "${XEN_REL}+stable"

DEFAULT_PREFERENCE ??= "-1"

require xen.inc
require xen-hypervisor.inc
