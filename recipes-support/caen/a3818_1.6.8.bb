DESCRIPTION = "A3818 PCI Express CONET2 Controller"
HOMEPAGE = "https://www.caen.it/products/a3818/"
LICENSE = "CLOSED"

inherit module

SRC_URI = " \
	file://A3818Drv-${PV}.tar.gz \
	file://Makefile \
	file://90-a3818.rules \
	"

S = "${WORKDIR}/A3818Drv-${PV}"

MODULES_MODULE_SYMVERS_LOCATION = "src"
EXTRA_OEMAKE += "-C ${MODULES_MODULE_SYMVERS_LOCATION}"

# KERNEL_MODULE_AUTOLOAD += " ${PN}"
RPROVIDES:${PN} += "kernel-module-${PN}"

do_configure:append() {
	install -m 0644 ${S}/include/a3818.h ${S}/${MODULES_MODULE_SYMVERS_LOCATION}
	install -m 0644 ${WORKDIR}/Makefile ${S}/${MODULES_MODULE_SYMVERS_LOCATION}
}

FILES:${PN} += "/etc/udev/rules.d"
do_install:append() {
	install -d ${D}${includedir}
	install -m 0644 ${S}/${MODULES_MODULE_SYMVERS_LOCATION}/a3818.h ${D}${includedir}

 	install -d ${D}${sysconfdir}/udev/rules.d/
 	install -m 0644 ${WORKDIR}/90-a3818.rules \
 		${D}${sysconfdir}/udev/rules.d/
}
