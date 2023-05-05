DESCRIPTION = "Provides BIOS upgrade and configuration files"
LICENSE = "CLOSED"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_HOST = "x86_64.*-linux"

RDEPENDS:${PN}:append:x10dru-iplus = "sum"
RDEPENDS:${PN}:append:x11dph-t = "sum"
RDEPENDS:${PN}:append:x11spw-tf = "sum"

SRC_URI = " file://bios_configuration.bin"
SRC_URI:append:x10dru-iplus = " https://www.supermicro.com/Bios/softfiles/15575/X10DRU2.427.zip;subdir=${BPN};name=bios-x10dru-iplus \
		https://www.supermicro.com/Bios/softfiles/14879/BMC_X10AST2400-C001MS_20211001_03.94_STD.zip;subdir=${BPN};name=bmc-x10dru-iplus"
SRC_URI:append:x11dph-t = " https://www.supermicro.com/Bios/softfiles/17249/X11DPH-I,T,Tq_3.8b_AS1.74.11_SUM2.10.0.zip;name=bios-x11dph-t"
SRC_URI:append:x11spw-tf = " https://www.supermicro.com/Bios/softfiles/16571/BIOS_X11SPW-0953_20221028_3.8a_STD.zip;subdir=${BPN};name=bios-x11spw-tf \
		https://www.supermicro.com/Bios/softfiles/16574/BMC_X11AST2500-4101MS_20221027_01.74.11_STDsp.zip;subdir=${BPN};name=bmc-x11spw-tf"
#SRC_URI:append:up-whl01 = " file://UPW1AM19.zip;name=bios-up"

SRC_URI[bios-x10dru-iplus.sha256sum] = "d24b8f6b7f4ed186bbca662751b7d80ae6efd014d1ba71b47d9c4370eaa39fb4"
SRC_URI[bmc-x10dru-iplus.sha256sum] = "80fcf01d2073cabe81118140a8494c8a65431dd5d20460c12272db110b5f8d21"
SRC_URI[bios-x11dph-t.sha256sum] = "70128f4e6a76c2c5e863d99eace18034301c8a8a68d4216c93376bb869a90ed9"
SRC_URI[bios-x11spw-tf.sha256sum] = "cc423035daa05a7eb90f39829bee55b59fd407b7503a4c6516b74aaee806db1e"
SRC_URI[bmc-x11spw-tf.sha256sum] = "9c9e2469c97c312dc35b07bd822f1d66c487bb4c1ca7e0296d3f119991372a03"
#SRC_URI[bios-up.sha256sum] = "ae36f0a560ab4fb0d60a1e45988e4989f6ee274d2d5ccacd9e0221e80dd3d3de"

S = "${WORKDIR}/${BPN}"
PACKAGES = "${BPN}"
INSANE_SKIP:${PN} += "already-stripped ldflags file-rdeps debug-files"

do_extract_x11dph_t_data() {
	unzip ${WORKDIR}/BIOS*.zip -d ${S}/
	unzip ${WORKDIR}/BMC*.zip -d ${S}/
}

python do_unpack:append:x11dph-t() {
    bb.build.exec_func('do_extract_x11dph_t_data', d)
}

do_install() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${WORKDIR}/bios_configuration.bin ${D}${datadir}/${BPN}
}

do_install:append:x10dru-iplus() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${S}/X10DRU2.427/DOS/X10DRU2.427 ${S}/BMC*/BMC*.bin \
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
