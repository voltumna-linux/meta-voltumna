SUMMARY = "Compatibility package for backport-iwlwifi libarc4 dependency"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "virtual/kernel"
RDEPENDS:${PN} = "kernel-module-libarc4"

inherit allarch

ALLOW_EMPTY:${PN} = "1"

RPROVIDES:${PN} = "backport-iwlwifikernel-module-libarc4-6.6.78-intel-pk-standard"

do_configure[noexec] = "1"
do_compile[noexec] = "1"
do_install[noexec] = "1"
