DESCRIPTION = "ARM Trusted Firmware"

LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM ?= "file://docs/license.rst;md5=189505435dbcdcc8caa63c46fe93fa89"

PROVIDES = "arm-trusted-firmware"

DEPENDS = "u-boot-tools"

inherit deploy

PACKAGE_ARCH = "${MACHINE_ARCH}"

ATF_PROT ?= "https"
ATF_BRANCH ?= "socfpga_v2.3"
ATF_REPO ?= "git://github.com/altera-fpga/arm-trusted-firmware.git"

SRC_URI = "${ATF_REPO};protocol=${ATF_PROT};branch=${ATF_BRANCH}"

S = "${WORKDIR}/git"

COMPATIBLE_MACHINE = "(agilex3|agilex5_dk_a5e065bb32aes1|agilex5_dk_a5e013bm16aea|agilex5_dk_a5e013bb32aes|agilex5_dk_a5e013bb32aes_5s|agilex5_mk_a5e065bb32aes1|agilex7_dk_si_agf014eb|agilex7_dk_si_agi027fc|agilex7_dk_dev_agm039fes|agilex7_dk_dev_agm039ea|agilex7_dk_dev_agf023fa|agilex5|stratix10_htile|n5x)"
ATFPLAT = "${MACHINE}"
ATFPLAT:agilex3 = "agilex3"
ATFPLAT:agilex5_dk_a5e065bb32aes1 = "agilex5"
ATFPLAT:agilex5_dk_a5e013bm16aea = "agilex5"
ATFPLAT:agilex5_dk_a5e013bb32aes = "agilex5"
ATFPLAT:agilex5_dk_a5e013bb32aes_5s = "agilex5"
ATFPLAT:agilex5_mk_a5e065bb32aes1 = "agilex5"
ATFPLAT:agilex7_dk_si_agf014eb = "agilex"
ATFPLAT:agilex7_dk_si_agi027fc = "agilex"
ATFPLAT:agilex7_dk_dev_agm039fes = "agilex"
ATFPLAT:agilex7_dk_dev_agm039ea = "agilex"
ATFPLAT:agilex7_dk_dev_agf023fa = "agilex"
ATFPLAT:stratix10_htile = "stratix10"

CFLAGS="-Wno-error=array-bounds"

# Let the Makefile handle setting up the CFLAGS and LDFLAGS as it is a standalone application
EXTRA_OEMAKE = 'CROSS_COMPILE="${TARGET_PREFIX}" PLAT="${ATFPLAT}" CFLAGS="${CFLAGS}" DEPRECATED=1'
# CFLAGS[unexport] = "1"
LDFLAGS[unexport] = "1"
AS[unexport] = "1"
LD[unexport] = "1"
PARALLEL_MAKE = ""

ALLOW_EMPTY:${PN} = "1"

do_configure[noexec] = "1"

do_compile() {
	oe_runmake -C ${S} bl31
}

do_deploy() {
	install -d ${DEPLOYDIR}
	install -m 0644 ${S}/build/${ATFPLAT}/release/bl31.bin ${DEPLOYDIR}/bl31.bin-${MACHINE}-${PV}-${PR}
	ln -sf bl31.bin-${MACHINE}-${PV}-${PR} ${DEPLOYDIR}/bl31.bin
}

addtask deploy after do_compile
