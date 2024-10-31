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
#SRC_URI:append:up-whl01 = " file://UPW1AM19.zip;name=bios-up"
SRC_URI:append:x12sdv-4c-sp6f = " https://www.supermicro.com/Bios/softfiles/22780/X12SDV-xC-SP6F_1.8_AS01.04.06_SUM2.14.0.zip;subdir=${BPN};name=bios-x12sdv-4c-sp6f"
SRC_URI:append:a3sev-4c-ln4 = " https://www.supermicro.com/Bios/softfiles/18174/BIOS_A3SEV-1C2A_20230808_1.3_STDsp.zip;subdir=${BPN};name=bios-a3sev-4c-ln4"

SRC_URI[bios-x10dru-iplus.sha256sum] = "d24b8f6b7f4ed186bbca662751b7d80ae6efd014d1ba71b47d9c4370eaa39fb4"
SRC_URI[bmc-x10dru-iplus.sha256sum] = "80fcf01d2073cabe81118140a8494c8a65431dd5d20460c12272db110b5f8d21"
SRC_URI[bios-x10drw-i.sha256sum] = "7379177cc6d30283c2b178d33f360d5522eb8e3a1badf9a6ab1cf837802dadeb"
SRC_URI[bmc-x10drw-i.sha256sum] = "d07982d5f684e6458c80c069f762245ab38163620a31c2c9b60a7c2edc4c0f4e"
SRC_URI[bios-x11dph-t.sha256sum] = "88878d2e35c1cf496e69c29871a82c5503de2375d17538c1002713fd9bb47842"
SRC_URI[bios-x11spw-tf.sha256sum] = "ff638e8a7396d2482a0fdd05f924251d06a48dfa535eb05c48cb0eb058e53719"
#SRC_URI[bios-up.sha256sum] = "ae36f0a560ab4fb0d60a1e45988e4989f6ee274d2d5ccacd9e0221e80dd3d3de"
SRC_URI[bios-x12sdv-4c-sp6f.sha256sum] = "30f34237163778a41e88afa68ebac591e18064ed9f9512c0574e6c0d8b390875"
SRC_URI[bios-a3sev-4c-ln4.sha256sum] = "d262f8dcd3b9ff85f09a2cb0025f2ab701b7ea63abb20a60bd792a1d1fce43e7"


S = "${WORKDIR}/${BPN}"
PACKAGES = "${BPN}"
INSANE_SKIP:${PN} += "already-stripped ldflags file-rdeps debug-files"

do_extract_bundled() {
	unzip ${S}/BIOS*.zip -d ${S}/
	unzip ${S}/BMC*.zip -d ${S}/
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
	install -m 0444 ${S}/BMC*.bin ${S}/BIOS*/BIOS*.bin \
		${D}${datadir}/${BPN}
}

do_install:append:x11spw-tf() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${S}/BMC*.bin ${S}/BIOS*.bin \
		${D}${datadir}/${BPN}
}

do_install:append:x12sdv-4c-sp6f() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${S}/BMC*.bin ${S}/BIOS*.bin \
		${D}${datadir}/${BPN}
}

do_install:append:a3sev-4c-ln4() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${S}/BIOS*.bin \
		${D}${datadir}/${BPN}
}
