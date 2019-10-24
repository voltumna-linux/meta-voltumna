FILES_${PN} += "${KERNEL_IMAGEDEST}/microcode*"

do_install_append() {
	install -d ${D}/${KERNEL_IMAGEDEST}
	install -m 644 ${WORKDIR}/microcode_${PV}.cpio ${D}/${KERNEL_IMAGEDEST}
	lnr ${D}/${KERNEL_IMAGEDEST}/microcode_${PV}.cpio ${D}/${KERNEL_IMAGEDEST}/microcode.cpio
}
