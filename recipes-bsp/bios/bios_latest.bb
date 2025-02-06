DESCRIPTION = "Provides BIOS upgrade and configuration files"
LICENSE = "CLOSED"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_HOST = "x86_64.*-linux"

RDEPENDS:${PN}:append:x10dru-iplus = "sum"
RDEPENDS:${PN}:append:x10drw-i = "sum"
RDEPENDS:${PN}:append:x11dph-t = "sum"
RDEPENDS:${PN}:append:x11spw-tf = "sum"
RDEPENDS:${PN}:append:x12sdv-4c-sp6f = "sum"
RDEPENDS:${PN}:append:a3sev-4c-ln4 = "sum"

SRC_URI = " file://bios_configuration.bin"
SRC_URI:append:x10dru-iplus = " https://www.supermicro.com/Bios/softfiles/15575/X10DRU2.427.zip;subdir=${BPN};name=bios-x10dru-iplus \
		https://www.supermicro.com/Bios/softfiles/14879/BMC_X10AST2400-C001MS_20211001_03.94_STD.zip;subdir=${BPN};name=bmc-x10dru-iplus"
SRC_URI:append:x10drw-i = " https://www.supermicro.com/Bios/softfiles/10581/X10DRW9_B22.zip;subdir=${BPN};name=bios-x10drw-i \
		https://www.supermicro.com/Bios/softfiles/12112/REDFISH_X10_389_20200623_unsigned.zip;subdir=${BPN};name=bmc-x10drw-i"
SRC_URI:append:x11dph-t = " https://www.supermicro.com/Bios/softfiles/22681/X11DPH-I,T,Tq_4.3_AS1.74.14_SUM2.13.0.zip;subdir=${BPN};name=bios-x11dph-t"
SRC_URI:append:x11spw-tf = " https://www.supermicro.com/Bios/softfiles/22624/X11SPW_4.4_AS01.74.15_SUM2.14.0.zip;subdir=${BPN};name=bios-x11spw-tf"
SRC_URI:append:up-whl01 = " https://downloads.up-community.org/download/up-xtreme-uefi-bios-v2-1/?wpdmdl=1054&ind=ecKW0_nM8nrydmuNytAW1RIUmj5aOiUe2fxxPUAD9itQKU2UYBGqicZeXYUpURsg1Sc6X-KFZ9Lp0EaBBT_pk_kUXIZnksIh49fZWcaTUUIWKHwFJHfvhSvWPND8w6So;;downloadfilename=UPW1AM21.zip;name=bios-up \
			file://BIOS_update_SOP.txt"
SRC_URI:append:x12sdv-4c-sp6f = " https://www.supermicro.com/Bios/softfiles/23875/X12SDV-xC-SP6F_1.9_AS01.04.10_SUM2.14.0-p8.zip;subdir=${BPN};name=bios-x12sdv-4c-sp6f"
SRC_URI:append:a3sev-4c-ln4 = " https://www.supermicro.com/Bios/softfiles/23899/BIOS_A3SEV-1C2A_20250115_1.9_STDsp.zip;subdir=${BPN};name=bios-a3sev-4c-ln4"

SRC_URI[bios-x10dru-iplus.sha256sum] = "d24b8f6b7f4ed186bbca662751b7d80ae6efd014d1ba71b47d9c4370eaa39fb4"
SRC_URI[bmc-x10dru-iplus.sha256sum] = "80fcf01d2073cabe81118140a8494c8a65431dd5d20460c12272db110b5f8d21"
SRC_URI[bios-x10drw-i.sha256sum] = "7379177cc6d30283c2b178d33f360d5522eb8e3a1badf9a6ab1cf837802dadeb"
SRC_URI[bmc-x10drw-i.sha256sum] = "d07982d5f684e6458c80c069f762245ab38163620a31c2c9b60a7c2edc4c0f4e"
SRC_URI[bios-x11dph-t.sha256sum] = "88878d2e35c1cf496e69c29871a82c5503de2375d17538c1002713fd9bb47842"
SRC_URI[bios-x11spw-tf.sha256sum] = "ff638e8a7396d2482a0fdd05f924251d06a48dfa535eb05c48cb0eb058e53719"
SRC_URI[bios-up.sha256sum] = "3372cb69885ec75ac3a75b4079a9370a5e918ecc0853b37eb879f809c67149f0"
SRC_URI[bios-x12sdv-4c-sp6f.sha256sum] = "f69fb22a71ae7fdc51a9f3b1a0e171d6cd54387df8203440c1680f34fb7d85e0"
SRC_URI[bios-a3sev-4c-ln4.sha256sum] = "92957fee73bee6b573fcc95d476b12a9108283fd764296092ee22fde45f2a984"


S = "${WORKDIR}/${BPN}"
PACKAGES = "${BPN}"
INSANE_SKIP:${PN} += "already-stripped ldflags file-rdeps debug-files"

do_extract() {
	unzip ${S}/BIOS*.zip -d ${S}/BIOS
}

do_extract_bundled() {
	unzip ${S}/BIOS*.zip -d ${S}/BIOS
	unzip ${S}/BMC*.zip -d ${S}/BMC
}

python do_unpack:append:x11dph-t() {
    bb.build.exec_func('do_extract_bundled', d)
}

python do_unpack:append:x11spw-tf() {
    bb.build.exec_func('do_extract_bundled', d)
}

python do_unpack:append:x12sdv-4c-sp6f() {
    bb.build.exec_func('do_extract_bundled', d)
}

python do_unpack:append:a3sev-4c-ln4() {
    bb.build.exec_func('do_extract', d)
}

do_install() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${WORKDIR}/bios_configuration.bin ${D}${datadir}/${BPN}
}

do_install:append:x10dru-iplus() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${S}/X10DRU*/DOS/X10DRU2.427 ${S}/BMC*/BMC*.bin \
		${D}${datadir}/${BPN}
}

do_install:append:x10drw-i() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${S}/DOS/X10DRW9.B22 ${S}/REDFISH*.bin \
		${D}${datadir}/${BPN}
}

do_install:append:x11dph-t() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${S}/BMC/BMC*.bin ${S}/BIOS/BIOS*/BIOS*.bin \
		${D}${datadir}/${BPN}
}

do_install:append:x11spw-tf() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${S}/BMC/BMC*.bin ${S}/BIOS/BIOS*.bin \
		${D}${datadir}/${BPN}
}

do_install:append:x12sdv-4c-sp6f() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${S}/BMC/BMC*.bin ${S}/BIOS/BIOS*.bin \
		${D}${datadir}/${BPN}
}

do_install:append:a3sev-4c-ln4() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${S}/BIOS/BIOS*/BIOS*.bin \
		${D}${datadir}/${BPN}
}

do_install:append:up-whl01() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${WORKDIR}/UPW1AM21/*.BIN \
		${WORKDIR}/BIOS_update_SOP.txt \
		${D}${datadir}/${BPN}
}
