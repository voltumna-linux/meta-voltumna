DESCRIPTION = "Supermicro Update Manager (SUM) is used for managing and configuring \
the BIOS/BMC firmware for Supermicro X9 generation motherboards and above."
HOMEPAGE = "https://www.supermicro.com/en/solutions/management-software/supermicro-update-manager"
LICENSE = "CLOSED"

COMPATIBLE_HOST = "x86_64.*-linux"

DIR = "698"
SUFFIX = "Linux_x86_64"
DATE = "20240215"
SRC_URI = "https://www.supermicro.com/Bios/sw_download/${DIR}/sum_${PV}_${SUFFIX}_${DATE}.tar.gz"
SRC_URI[sha256sum] = "79cf26203493bb6a5b64fc508d9696151f89e08b79120a582d337bd5aae6c0a1"

S = "${WORKDIR}/${BPN}_${PV}_${SUFFIX}"
PACKAGES = "${BPN}"
INSANE_SKIP:${PN} = "already-stripped ldflags debug-files file-rdeps"

do_install() {
	install -d ${D}${datadir}/${BPN}
	install -m 0744 ${S}/sum ${D}${datadir}/${BPN}
	pdftotext ${S}/SUM_UserGuide.pdf ${D}${datadir}/${BPN}/SUM_UserGuide.txt
}
