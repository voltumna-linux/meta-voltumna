DESCRIPTION = "Supermicro Update Manager (SUM) is used for managing and configuring \
the BIOS/BMC firmware for Supermicro X9 generation motherboards and above."
HOMEPAGE = "https://www.supermicro.com/en/solutions/management-software/supermicro-update-manager"
LICENSE = "LicenseRef-sum-CLOSED"
LIC_FILES_CHKSUM = "file://SUM_UserGuide.pdf;md5=4292cf4fc6e164d4714fab454291a0c5"

COMPATIBLE_HOST = "x86_64.*-linux"

# The Supermicro download center lists versions in <span> markup, not in
# links, so scrape the page text through upstream-page-check (the regex picks
# the SUM entry, not "SUM for UEFI" nor the SUM extension package). DIR, DATE
# and the checksum below are per release and cannot be derived from the
# version: update them by hand together with PV when the check reports a
# newer version.
inherit upstream-page-check
UPSTREAM_CHECK_URI = "https://www.supermicro.com/en/support/resources/downloadcenter/smsdownload"
UPSTREAM_CHECK_REGEX = "<h5[^>]*>Supermicro Update Manager \(SUM\)</h5>.{0,4000}?Version: (?P<pver>\d+(\.\d+)+)"

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
