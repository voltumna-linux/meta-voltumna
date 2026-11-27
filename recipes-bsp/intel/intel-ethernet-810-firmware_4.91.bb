DESCRIPTION = "Provides the Non-Volatile Memory (NVM) Update Utility for Intel Ethernet Network Adapter E810 Series."
HOMEPAGE = "https://www.intel.com/content/www/us/en/download/19624/non-volatile-memory-nvm-update-utility-for-intel-ethernet-network-adapter-e810-series.html"
LICENSE = "LicenseRef-intel-ethernet-810-firmware-CLOSED"
LIC_FILES_CHKSUM = "file://E810/Linux_x64/license.txt;md5=e475236e1d192f96e69473e79f969226"

# The Intel page exposes the download URL (and hence the version) inside a
# data-href attribute, not in a link the standard check can see: scrape the
# page text through upstream-page-check. NUM and the checksum below are per
# release and cannot be derived from the version: update them by hand together
# with PV when the check reports a newer version.
inherit upstream-page-check
UPSTREAM_CHECK_URI = "${HOMEPAGE}"
UPSTREAM_CHECK_REGEX = "E810_NVMUpdatePackage_v(?P<pver>\d+_\d+)"

PV_MAJOR = "${@d.getVar('PV').split('.')[0]}"
PV_MINOR = "${@d.getVar('PV').split('.')[1]}"
NUM = "871942"
SRC_URI = "https://downloadmirror.intel.com/${NUM}/E810_NVMUpdatePackage_v${PV_MAJOR}_${PV_MINOR}.zip"
SRC_URI[sha256sum] = "c68f64f2a0b98b1d12b113a5d4d317967860834369b741fa74bfdf1b3684fefd"

COMPATIBLE_HOST = "x86_64.*-linux"

PACKAGES = "${BPN}"

INSANE_SKIP:${PN} = "already-stripped"

do_extract_data() {
	install -d ${S}
	tar zxf ${UNPACKDIR}/E810_NVMUpdatePackage_v${PV_MAJOR}_${PV_MINOR}_Linux.tar.gz -C "${S}"
}

python do_unpack:append() {
    bb.build.exec_func('do_extract_data', d)
}

do_install() {
	install -m 0755 -d ${D}${datadir}/${BPN}
	install -m 0644 ${S}/*/*/* ${D}${datadir}/${BPN}
	chmod 755 ${D}${datadir}/${BPN}/nvmupdate64e
}
