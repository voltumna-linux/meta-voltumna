DESCRIPTION = "Provides the Non-Volatile Memory (NVM) Update Utility for Intel Ethernet Network Adapter E810 Series."
HOMEPAGE = "https://www.intel.com/content/www/us/en/download/19624/non-volatile-memory-nvm-update-utility-for-intel-ethernet-network-adapter-e810-series.html"
LICENSE = "CLOSED"

PV_MAJOR = "${@d.getVar('PV').split('.')[0]}"
PV_MINOR = "${@d.getVar('PV').split('.')[1]}"
NUM = "832157"
SRC_URI = "https://downloadmirror.intel.com/${NUM}/E810_NVMUpdatePackage_v${PV_MAJOR}_${PV_MINOR}.zip"
SRC_URI[sha256sum] = "805f79673fdf95b0fdea5d558a58828b6ced62a52d1f99edb9bd0727cc4ad822"

COMPATIBLE_HOST = "x86_64.*-linux"

PACKAGES = "${BPN}"

INSANE_SKIP:${PN} = "already-stripped"

do_extract_data() {
	tar zxf ${WORKDIR}/E810_NVMUpdatePackage_v${PV_MAJOR}_${PV_MINOR}_Linux.tar.gz -C "${S}"
}

python do_unpack:append() {
    bb.build.exec_func('do_extract_data', d)
}

do_install() {
	install -m 0755 -d ${D}${datadir}/${BPN}
	install -m 0644 ${S}/*/*/* ${D}${datadir}/${BPN}
	chmod 755 ${D}${datadir}/${BPN}/nvmupdate64e
}
