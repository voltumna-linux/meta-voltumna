DESCRIPTION = "Provides the Non-Volatile Memory (NVM) Update Utility for Intel Ethernet Network Adapter X550 Series."
HOMEPAGE = "https://www.intel.com/content/www/us/en/download/19358/non-volatile-memory-nvm-update-utility-for-intel-ethernet-network-adapter-x550-series.html"
LICENSE = "CLOSED"

PV_MAJOR = "${@d.getVar('PV').split('.')[0]}"
PV_MINOR = "${@d.getVar('PV').split('.')[1]}"
NUM = "727462"
SRC_URI = "https://downloadmirror.intel.com/${NUM}/X550_NVMUpdatePackage_v${PV_MAJOR}_${PV_MINOR}.zip"
SRC_URI[sha1sum] = "c4afb238cac445ea08090caecd0ef648baf3b544"
COMPATIBLE_HOST = "x86_64.*-linux"

PACKAGES = "${BPN}"

INSANE_SKIP:${PN} = "already-stripped"

do_extract_data() {
	tar zxf ${UNPACKDIR}/*_Linux.tar.gz -C "${S}"
}

python do_unpack:append() {
    bb.build.exec_func('do_extract_data', d)
}

do_install() {
	install -m 0755 -d ${D}${datadir}/${BPN}
	install -m 0644 ${S}/*/*/* ${D}${datadir}/${BPN}
	chmod 755 ${D}${datadir}/${BPN}/nvmupdate64e
}
