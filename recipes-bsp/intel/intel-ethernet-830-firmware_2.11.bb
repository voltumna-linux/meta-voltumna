DESCRIPTION = "Provides the Non-Volatile Memory (NVM) Update Utility for Intel Ethernet Network Adapter E830 Series."
HOMEPAGE = "https://www.intel.com/content/www/us/en/download/859202/nvm-update-utility-for-intel-ethernet-e830-and-e835-series.html"
LICENSE = "CLOSED"

PV_MAJOR = "${@d.getVar('PV').split('.')[0]}"
PV_MINOR = "${@d.getVar('PV').split('.')[1]}"
NUM = "923583"
SRC_URI = "https://downloadmirror.intel.com/${NUM}/E830_E835_NVMUpdatePackage_v${PV_MAJOR}_${PV_MINOR}.zip"
SRC_URI[sha256sum] = "0e1514e7d8846894945ed9b8a78829d1093f246535bde3d276f931223baf11ab"

COMPATIBLE_HOST = "x86_64.*-linux"

PACKAGES = "${BPN}"

INSANE_SKIP:${PN} = "already-stripped"

do_extract_data() {
	install -d ${S}
	tar zxf ${UNPACKDIR}/E830_E835_NVMUpdatePackage_v${PV_MAJOR}_${PV_MINOR}_Linux.tar.gz -C "${S}"
}

python do_unpack:append() {
    bb.build.exec_func('do_extract_data', d)
}

do_install() {
	install -m 0755 -d ${D}${datadir}/${BPN}
	install -m 0644 ${S}/*/*/* ${D}${datadir}/${BPN}
	chmod 755 ${D}${datadir}/${BPN}/nvmupdate64e
}
