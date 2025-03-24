FILES:${PN} += "${KERNEL_IMAGEDEST}/microcode*"

do_install:append() {
	install -d ${D}/${KERNEL_IMAGEDEST}
	install -m 644 ${UNPACKDIR}/microcode_${PV}.cpio ${D}/${KERNEL_IMAGEDEST}
	ln -sr ${D}/${KERNEL_IMAGEDEST}/microcode_${PV}.cpio ${D}/${KERNEL_IMAGEDEST}/microcode.cpio
}
