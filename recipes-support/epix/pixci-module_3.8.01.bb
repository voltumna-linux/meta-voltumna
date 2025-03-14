DESCRIPTION = "PIXCI Frame Grabber Driver"
HOMEPAGE = "https://www.epixinc.com/products/pixci_drivers.htm"
LICENSE = "CLOSED"

SRC_URI = " \
    https://www.epixinc.com/support/files/downloads/xcaplnx_x86_64.bin \
    file://Makefile \
    "

SRC_URI[sha256sum] = "67a65af19fdbb898658547cac05e7a775e6431e1c920768623a9811e70f6ddea"

COMPATIBLE_HOST = "x86_64.*-linux"
S = "${WORKDIR}/epix"

do_extract_data() {
	chmod +x ${WORKDIR}/xcaplnx_x86_64.bin
	${WORKDIR}/xcaplnx_x86_64.bin << "EOF"
Next
No
${S}
Next
Cancel
EOF
	cp ${WORKDIR}/Makefile ${S}/drivers/x86_64/src_5.13
}

python do_unpack:append() {
    bb.build.exec_func('do_extract_data', d)
}

inherit module

RPROVIDES:${PN} += "kernel-module-pixci"

MODULES_MODULE_SYMVERS_LOCATION = "drivers/x86_64/src_5.13"
EXTRA_OEMAKE += "-C ${MODULES_MODULE_SYMVERS_LOCATION}"
MAKE_TARGETS = ""
MODULES_INSTALL_TARGET = ""

do_install() {
	cd ${S}/${MODULES_MODULE_SYMVERS_LOCATION}
	install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/misc
	install -m 0644 pixci_x86_64.ko ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/misc/pixci.ko
}
