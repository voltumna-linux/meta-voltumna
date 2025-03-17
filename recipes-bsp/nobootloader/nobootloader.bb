SUMMARY = "No bootloader"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit deploy

PROVIDES = "virtual/bootloader"

# COMPATIBLE_HOST = ".*-linux"

S = "${WORKDIR}"

INHIBIT_DEFAULT_DEPS = "1"
ALLOW_EMPTY:${PN} = "1"

do_configure() {
	:
}

do_compile() {
	:
}

do_install() {
	:
}

do_deploy() {
	:
}

addtask deploy after do_install
