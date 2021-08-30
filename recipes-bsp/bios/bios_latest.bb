DESCRIPTION = "Provides BIOS upgrade and configuration files"
LICENSE = "CLOSED"

PACKAGE_ARCH = "${MACHINE_ARCH}"

# 3.5
SRC_URI_append_ssg-6039p-e1cr16h = " file://bios_configuration.bin \
	https://www.supermicro.com/Bios/softfiles/14172/X11DPH-I,T,Tq_3.5_AS1.73.11_SUM2.5.2.zip;name=bios-ssg"
SRC_URI_append_sys-5019p-wtr = " file://bios_configuration.bin \
	https://www.supermicro.com/Bios/softfiles/14328/BIOS_X11SPW-0953_20210518_3.5_STD.zip;name=bios-sys"
# 1.9
# SRC_URI_append_up-whl01 = " https://aaeon365-my.sharepoint.com/personal/software_aaeon_eu/_layouts/15/download.aspx?SourceUrl=%2Fpersonal%2Fsoftware%5Faaeon%5Feu%2FDocuments%2FDownloads%2FBIOS%2FUP%20Xtreme%2FUPW1AM19%2Ezip;name=bios-up"

SRC_URI[bios-ssg.sha256sum] = "01005155d3525a74ce118d46f9a0e849ea249098e7913049e5e98bf310bcd4f6"
SRC_URI[bios-sys.sha256sum] = "29f690eef3fa19436f0faf62b6070b0f39c87e8a40dffef4d9d32f5119ece72e"
# SRC_URI[bios-up.sha256sum] = "ae36f0a560ab4fb0d60a1e45988e4989f6ee274d2d5ccacd9e0221e80dd3d3de"

COMPATIBLE_HOST = "x86_64.*-linux"

PACKAGES = "${BPN}"

do_extract_data() {
	unzip ${WORKDIR}/BIOS*.zip -d ${WORKDIR}/
}

python do_unpack_append_ssg-6039p-e1cr16h() {
    bb.build.exec_func('do_extract_data', d)
}

do_install() {
	install -m 0755 -d ${D}${datadir}/${BPN}
	install -m 0644 ${WORKDIR}/bios_configuration.bin ${WORKDIR}/BIOS*/* \
		${D}${datadir}/${BPN}
}
