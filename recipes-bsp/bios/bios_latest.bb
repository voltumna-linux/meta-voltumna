DESCRIPTION = "Provides BIOS upgrade and configuration files"
LICENSE = "CLOSED"

PACKAGE_ARCH = "${MACHINE_ARCH}"

SRC_URI_append = " file://bios_configuration.bin"
# 3.5
SRC_URI_append_x11dph-t = " file://X11DPH-I,T,Tq_3.5_AS1.73.11_SUM2.5.2.zip;name=bios-x11dph-t"
SRC_URI_append_x11spw-tf = " file://BIOS_X11SPW-0953_20210518_3.5_STD.zip;name=bios-x11spw-tf"
# 1.9
SRC_URI_append_up-whl01 = " file://UPW1AM19.zip;name=bios-up"

SRC_URI[bios-x11dph-t.sha256sum] = "01005155d3525a74ce118d46f9a0e849ea249098e7913049e5e98bf310bcd4f6"
SRC_URI[bios-x11spw-tf.sha256sum] = "29f690eef3fa19436f0faf62b6070b0f39c87e8a40dffef4d9d32f5119ece72e"
SRC_URI[bios-up.sha256sum] = "ae36f0a560ab4fb0d60a1e45988e4989f6ee274d2d5ccacd9e0221e80dd3d3de"

COMPATIBLE_HOST = "x86_64.*-linux"

PACKAGES = "${BPN}"

do_extract_data() {
	unzip ${WORKDIR}/BIOS*.zip -d ${WORKDIR}/
}

python do_unpack_append_x11dph-t() {
    bb.build.exec_func('do_extract_data', d)
}

do_install() {
	install -m 0755 -d ${D}${datadir}/${BPN}
	install -m 0644 ${WORKDIR}/bios_configuration.bin ${WORKDIR}/BIOS*/* \
		${D}${datadir}/${BPN}
}

do_install_up-whl01() {
	install -m 0755 -d ${D}${datadir}/${BPN}
	install -m 0644 ${WORKDIR}/bios_configuration.bin ${WORKDIR}/UP*/* \
		${D}${datadir}/${BPN}
}
