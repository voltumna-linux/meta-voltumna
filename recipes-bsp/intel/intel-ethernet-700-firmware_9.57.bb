DESCRIPTION = "Provides the Non-Volatile Memory (NVM) Update Utility for Intel Ethernet Network Adapter 700 Series."
HOMEPAGE = "https://www.intel.com/content/www/us/en/download/18190/non-volatile-memory-nvm-update-utility-for-intel-ethernet-network-adapter-700-series.html"
LICENSE = "CLOSED"

PV_MAJOR = "${@d.getVar('PV').split('.')[0]}"
PV_MINOR = "${@d.getVar('PV').split('.')[1]}"
NUM = "920683"
SRC_URI = "https://downloadmirror.intel.com/${NUM}/700Series_NVMUpdatePackage_v${PV_MAJOR}_${PV_MINOR}.zip"
SRC_URI[sha256sum] = "f0f946f25067030b601140313817d34dec5bf5617c9a1fc27541c2fc7c1aa58d"
COMPATIBLE_HOST = "x86_64.*-linux"

PACKAGES = "${BPN}"

INSANE_SKIP:${PN} = "already-stripped"

do_extract_data() {
	install -d ${S}
	tar zxf ${WORKDIR}/*_Linux.tar.gz -C "${S}"
}

python do_unpack:append() {
    bb.build.exec_func('do_extract_data', d)
}

do_install() {
	install -m 0755 -d ${D}${datadir}/${BPN}
	install -m 0644 ${S}/*/*/* ${D}${datadir}/${BPN}
	chmod 755 ${D}${datadir}/${BPN}/nvmupdate64e
}
