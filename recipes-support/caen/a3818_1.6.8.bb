DESCRIPTION = "A3818 PCI Express CONET2 Controller"
HOMEPAGE = "https://www.caen.it/products/a3818/"
LICENSE = "CLOSED"

inherit module

SRC_URI = " \
        https://www.elettra.eu/images/Documents/Voltumna/intranet/predownloaded-tarballs/A3818Drv-${PV}.tar.gz \
	file://fix-build-system.patch \
	file://90-a3818.rules \
	"
SRC_URI[sha256sum] = "bf32eb92c4c6dc6d007c7b4e83f73e22244c84965094b18e55894c63c0ca3715"
S = "${WORKDIR}/A3818Drv-${PV}"

MODULES_MODULE_SYMVERS_LOCATION = "src"
EXTRA_OEMAKE += "-C ${MODULES_MODULE_SYMVERS_LOCATION}"

# KERNEL_MODULE_AUTOLOAD += " ${PN}"
RPROVIDES:${PN} += "kernel-module-${PN}"

FILES:${PN} += "/etc/udev/rules.d"
do_install:append() {
	install -d ${D}${includedir}
	install -m 0644 ${S}/${MODULES_MODULE_SYMVERS_LOCATION}/a3818.h ${D}${includedir}

 	install -d ${D}${sysconfdir}/udev/rules.d/
 	install -m 0644 ${WORKDIR}/90-a3818.rules \
 		${D}${sysconfdir}/udev/rules.d/
}
