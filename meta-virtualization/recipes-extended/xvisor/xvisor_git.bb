SUMMARY = "Xvisor is an open-source type-1 hypervisor, which aims at providing a monolithic, light-weight, portable, and flexible virtualization solution."
DESCRIPTION = "Xvisor primarily supports Full virtualization hence, supports a wide range of unmodified guest operating systems. Paravirtualization is optional for Xvisor and will be supported in an architecture independent manner (such as VirtIO PCI/MMIO devices) to ensure no-change in guest OS for using paravirtualization."
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=b234ee4d69f5fce4486a80fdaf4a4263"
DEPENDS += "dtc-native dosfstools-native mtools-native"

require xvisor-configs.inc

inherit autotools-brokensep

PV = "0.3.2+git"

# This version support the RISC-V v0.5.0 Hypervisor extensions
SRCREV = "355c79a07d9c1b783962ebf47b9b18194b7d40bd"
SRC_URI = "git://github.com/xvisor/xvisor.git;branch=master;protocol=https \
    file://0001-TESTS-Don-t-specify-mabi-or-march-for-RISC-V.patch \
"

EXTRA_OEMAKE += "ARCH=\"${@map_xvisor_arch(d.getVar('TARGET_ARCH'), d)}\" I=${D}"

CONFIG = "${@get_oemake_config(d.getVar('TARGET_ARCH'), d)}"

do_configure() {
    oe_runmake ${CONFIG}
}

do_install:append() {
    install -d ${D}
    install -m 755 ${B}/build/vmm.* ${D}/

    # We don't need this
    rm ${D}/system.map
}

do_deploy () {
    install -d ${DEPLOY_DIR_IMAGE}
    install -m 755 ${D}/vmm.* ${DEPLOY_DIR_IMAGE}/

    if [[ -f "${D}/*.dtb" ]]; then
        install -m 755 ${D}/*.dtb ${DEPLOY_DIR_IMAGE}/
    fi
}

addtask deploy after do_install

FILES:${PN} += "/vmm.*"
FILES:${PN} += "/*.dtb"

COMPATIBLE_HOST = "(aarch64|riscv64|riscv32).*"
INHIBIT_PACKAGE_STRIP = "1"

# ERROR: xvisor-git-r0 do_package_qa: QA Issue: File /vmm.elf in package xvisor doesn't have GNU_HASH (didn't pass LDFLAGS?) [ldflags]
# ERROR: xvisor-git-r0 do_package_qa: QA Issue: xvisor: ELF binary /vmm.elf has relocations in .text [textrel]
# ERROR: xvisor-0.3.2+git-r0 do_package_qa: QA Issue: File /vmm.elf in package xvisor contains reference to TMPDIR [buildpaths]
# ERROR: xvisor-0.3.2+git-r0 do_package_qa: QA Issue: File /vmm.bin in package xvisor contains reference to TMPDIR [buildpaths]
# ERROR: xvisor-0.3.2+git-r0 do_package_qa: QA Issue: File /.debug/vmm.elf in package xvisor-dbg contains reference to TMPDIR [buildpaths]
INSANE_SKIP:${PN} += "buildpaths ldflags textrel"
INSANE_SKIP:${PN}-dbg += "buildpaths"
