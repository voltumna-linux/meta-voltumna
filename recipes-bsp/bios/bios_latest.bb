DESCRIPTION = "Provides BIOS upgrade and configuration files"
LICENSE = "CLOSED"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_HOST = "x86_64.*-linux"

RDEPENDS:${PN}:append:x10dru-iplus = "sum"

SRC_URI = " file://bios_configuration.bin"
SRC_URI:append:x10dru-iplus = " https://www.supermicro.com/Bios/softfiles/15575/X10DRU2.427.zip;subdir=${BPN};name=bios-x10dru-iplus \
		https://www.supermicro.com/Bios/softfiles/14879/BMC_X10AST2400-C001MS_20211001_03.94_STD.zip;subdir=${BPN};name=bmc-x10dru-iplus"
#SRC_URI:append:x11dph-t = " file://X11DPH-I,T,Tq_3.6_AS1.74.02_SUM2.7.0.zip;name=bios-x11dph-t"
#SRC_URI:append:x11spw-tf = " file://BIOS_X11SPW-0953_20210518_3.5_STD.zip;name=bios-x11spw-tf"
#SRC_URI:append:up-whl01 = " file://UPW1AM19.zip;name=bios-up"

SRC_URI[bios-x10dru-iplus.sha256sum] = "d24b8f6b7f4ed186bbca662751b7d80ae6efd014d1ba71b47d9c4370eaa39fb4"
SRC_URI[bmc-x10dru-iplus.sha256sum] = "80fcf01d2073cabe81118140a8494c8a65431dd5d20460c12272db110b5f8d21"
#SRC_URI[bios-x11dph-t.sha256sum] = "d76d0f296f6bf75c4ad8d69eda541781f6dee62dcc244b5779449a152d820ac1"
#SRC_URI[bios-x11spw-tf.sha256sum] = "29f690eef3fa19436f0faf62b6070b0f39c87e8a40dffef4d9d32f5119ece72e"
#SRC_URI[bios-up.sha256sum] = "ae36f0a560ab4fb0d60a1e45988e4989f6ee274d2d5ccacd9e0221e80dd3d3de"

S = "${WORKDIR}/${BPN}"
PACKAGES = "${BPN}"
INSANE_SKIP:${PN} += "already-stripped ldflags file-rdeps debug-files"

#do_extract_x11dph_t_data() {
#	unzip ${WORKDIR}/BIOS*.zip -d ${S}/
#	unzip ${WORKDIR}/BMC*.zip -d ${S}/
#	tar zxf ${WORKDIR}/sum*Linux*.tar.gz -C ${S}/
#}

#python do_unpack:append:x11dph-t() {
#    bb.build.exec_func('do_extract_x11dph_t_data', d)
#}

do_install() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${WORKDIR}/bios_configuration.bin ${D}${datadir}/${BPN}
}

do_install:append:x10dru-iplus() {
	install -d ${D}${datadir}/${BPN}
	install -m 0444 ${S}/X10DRU2.427/DOS/X10DRU2.427 ${S}/BMC*/BMC*.bin \
		${D}${datadir}/${BPN}
}

#do_install:append:x11dph-t() {
#	install -d ${D}${sbindir}
#	install -m 0744 ${S}/sum*Linux*/sum ${S}/2.08/linux/x64/AlUpdate \
#		${D}${sbindir}
#	
#	install -d ${D}${sbindir}/acpica_bin
#	install -m 0744 ${S}/sum*Linux*/acpica_bin/acpi* ${D}${sbindir}/acpica_bin/
#
#	install -d ${D}${datadir}/${BPN}
#	install -m 0444 ${S}/BMC*.bin ${S}/BIOS*/BIOS*.bin \
#		${D}${datadir}/${BPN}
#	pdftotext ${S}/sum*Linux*/SUM_UserGuide.pdf \
#		${D}${datadir}/${BPN}/SUM_UserGuide.txt
#	pdftotext ${S}/IPMI*Firmware*Update_NEW.pdf \
#		${D}${datadir}/${BPN}/IPMI_Firmware_Update_NEW.txt
#}
