include andor3.inc

inherit module

RPROVIDES:${PN} += "kernel-module-bitflow"

SRC_URI:append = " \
	file://90-andor.rules \
	file://90-shamrock.rules \
	file://Makefile \
	"

MODULES_MODULE_SYMVERS_LOCATION = "bitflow/drv"
EXTRA_OEMAKE += "-C ${MODULES_MODULE_SYMVERS_LOCATION}"

do_compile:prepend() {
    cp ${WORKDIR}/Makefile ${S}/bitflow/drv
}

FILES:${PN} += " \
	${sysconfdir}/andor3 \
	${sysconfdir}/udev/rules.d \
	"

do_install() {
	cd ${S}/bitflow/drv
	install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/misc
	install -m 0644 bitflow.ko ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/misc

	install -d ${D}${sysconfdir}/udev/rules.d/
	install -m 0644 ${WORKDIR}/*.rules ${D}${sysconfdir}/udev/rules.d/
}
