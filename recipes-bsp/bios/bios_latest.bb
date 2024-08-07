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
SRC_URI:append:x11dph-t = " https://www.supermicro.com/Bios/softfiles/20072/X11DPH-I,T,Tq_4.2_AS1.74.14_SUM2.13.0.zip;name=bios-x11dph-t"
SRC_URI:append:x11spw-tf = " https://www.supermicro.com/Bios/softfiles/16571/BIOS_X11SPW-0953_20221028_3.8a_STD.zip;subdir=${BPN};name=bios-x11spw-tf \
		https://www.supermicro.com/Bios/softfiles/16574/BMC_X11AST2500-4101MS_20221027_01.74.11_STDsp.zip;subdir=${BPN};name=bmc-x11spw-tf"
SRC_URI:append:up-whl01 = " https://newdata.aaeon.com.tw/DOWNLOAD/BIOS/UP%20Xtreme(UP-WHL01)/UPW1AM21.zip;name=bios-up"
SRC_URI:append:x12sdv-4c-sp6f = " https://www.supermicro.com/Bios/softfiles/20489/BIOS_X12SDV-xC-SP6F-1C18_20240119_1.6a_STDsp.zip;subdir=${BPN};name=bios-x12sdv-4c-sp6f \
		https://www.supermicro.com/Bios/softfiles/19916/BMC_X12AST2600-F201MS_20231121_01.00.01_STDsp.zip;subdir=${BPN};name=bmc-x12sdv-4c-sp6f"
SRC_URI:append:a3sev-4c-ln4 = " https://www.supermicro.com/Bios/softfiles/18174/BIOS_A3SEV-1C2A_20230808_1.3_STDsp.zip;subdir=${BPN};name=bios-a3sev-4c-ln4"

#SRC_URI[bios-x10dru-iplus.sha256sum] = "d24b8f6b7f4ed186bbca662751b7d80ae6efd014d1ba71b47d9c4370eaa39fb4"
#SRC_URI[bmc-x10dru-iplus.sha256sum] = "80fcf01d2073cabe81118140a8494c8a65431dd5d20460c12272db110b5f8d21"
#SRC_URI[bios-x10drw-i.sha256sum] = "7379177cc6d30283c2b178d33f360d5522eb8e3a1badf9a6ab1cf837802dadeb"
#SRC_URI[bmc-x10drw-i.sha256sum] = "d07982d5f684e6458c80c069f762245ab38163620a31c2c9b60a7c2edc4c0f4e"
SRC_URI[bios-x11dph-t.sha256sum] = "a9001de1d15a702530df15f5778d2dd8909094d1eefd1dd0f2990eff295ad155"
#SRC_URI[bios-x11spw-tf.sha256sum] = "cc423035daa05a7eb90f39829bee55b59fd407b7503a4c6516b74aaee806db1e"
#SRC_URI[bmc-x11spw-tf.sha256sum] = "9c9e2469c97c312dc35b07bd822f1d66c487bb4c1ca7e0296d3f119991372a03"
SRC_URI[bios-up.sha256sum] = "3372cb69885ec75ac3a75b4079a9370a5e918ecc0853b37eb879f809c67149f0"
#SRC_URI[bios-x12sdv-4c-sp6f.sha256sum] = "77a3fc2952952fea67295022ca3bc8e762d8736613ab3d3b62f4ef20ba55edb9"
#SRC_URI[bmc-x12sdv-4c-sp6f.sha256sum] = "71bf3125a864130d103fae28e5a031ce149624f3526498cf9341595d09ce3936"
#SRC_URI[bios-a3sev-4c-ln4.sha256sum] = "d262f8dcd3b9ff85f09a2cb0025f2ab701b7ea63abb20a60bd792a1d1fce43e7"

PACKAGES = "${BPN}"
INSANE_SKIP:${PN} += "already-stripped ldflags file-rdeps debug-files"

do_extract_supermicro() {
	unzip ${WORKDIR}/BIOS*.zip -d ${WORKDIR}
	unzip ${WORKDIR}/BMC*.zip -d ${WORKDIR}
}

python do_unpack:append:x11dph-t() {
    bb.build.exec_func('do_extract_supermicro', d)
}

do_install() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${WORKDIR}/bios_configuration.bin ${D}${datadir}/${BPN}
}

do_install:append:up-whl01() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${WORKDIR}/UP*/* ${D}${datadir}/${BPN}
}

do_install:append:x11dph-t() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${WORKDIR}/BMC*.bin ${WORKDIR}/BIOS*/BIOS*.bin \
		${D}${datadir}/${BPN}
}

#do_install:append:x10dru-iplus() {
#	install -d ${D}${datadir}/${BPN}
#	install -m 0444 ${S}/X10DRU*/DOS/X10DRU2.427 ${S}/BMC*/BMC*.bin \
#		${D}${datadir}/${BPN}
#}
#
#do_install:append:x10drw-i() {
#	install -d ${D}${datadir}/${BPN}
#	install -m 0444 ${S}/DOS/X10DRW9.B22 ${S}/REDFISH*.bin \
#		${D}${datadir}/${BPN}
#}

#do_install:append:x11spw-tf() {
#	install -d ${D}${datadir}/${BPN}
#	install -m 0444 ${S}/BMC*.bin ${S}/BIOS*.bin \
#		${D}${datadir}/${BPN}
#}
#
#do_install:append:x12sdv-4c-sp6f() {
#	install -d ${D}${datadir}/${BPN}
#	install -m 0444 ${S}/BMC*.bin ${S}/BIOS*.bin \
#		${D}${datadir}/${BPN}
#}
#
#do_install:append:a3sev-4c-ln4() {
#	install -d ${D}${datadir}/${BPN}
#	install -m 0444 ${S}/BIOS*.bin \
#		${D}${datadir}/${BPN}
#}
