DESCRIPTION = "Supermicro Update Manager (SUM) is used for managing and configuring \
the BIOS/BMC firmware for Supermicro X9 generation motherboards and above."
HOMEPAGE = "https://www.supermicro.com/en/solutions/management-software/supermicro-update-manager"
LICENSE = "LicenseRef-sum-CLOSED"
LIC_FILES_CHKSUM = "file://SUM_UserGuide.pdf;md5=4292cf4fc6e164d4714fab454291a0c5"

COMPATIBLE_HOST = "x86_64.*-linux"

DIR = "1026"
SUFFIX = "Linux_x86_64"
DATE = "20251104"
SRC_URI = "https://www.supermicro.com/Bios/sw_download/${DIR}/sum_${PV}_${SUFFIX}_${DATE}.tar.gz"
SRC_URI[sha256sum] = "6d19460eba5e69cfd23797807c3821e38739c3d26220a6c40dc6a243893483e2"

S = "${UNPACKDIR}/${BPN}_${PV}_${SUFFIX}"
PACKAGES = "${BPN}"
INSANE_SKIP:${PN} = "already-stripped ldflags debug-files file-rdeps"

do_install() {
	install -d ${D}${datadir}/${BPN}
	install -m 0744 ${S}/sum ${D}${datadir}/${BPN}
	pdftotext ${S}/SUM_UserGuide.pdf ${D}${datadir}/${BPN}/SUM_UserGuide.txt
}
