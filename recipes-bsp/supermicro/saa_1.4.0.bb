DESCRIPTION = "SuperServer Automation Assistant (SAA) is the powerful CLI \
(Command-Line Interface) based utility that eases the management effort \
for IT Administrator to easily deploy, configure, and update the managed \
systems from single node to datacenter scale."
HOMEPAGE = "https://www.supermicro.com/en/solutions/management-software/superserver-automation-assistant"
LICENSE = "CLOSED"

COMPATIBLE_HOST = "x86_64.*-linux"

DIR = "1007"
SUFFIX = "Linux_x86_64"
DATE = "20251022"
SRC_URI = "https://www.supermicro.com/Bios/sw_download/${DIR}/saa_${PV}_${SUFFIX}_${DATE}.tar.gz"
SRC_URI[sha256sum] = "fb047601c4d92c9046dd9db9ba3715d10d8fa8ec8ee73d97722dffefa459757c"

S = "${UNPACKDIR}/${BPN}_${PV}_${SUFFIX}"
PACKAGES = "${BPN}"
INSANE_SKIP:${PN} = "already-stripped ldflags debug-files file-rdeps"

do_install() {
	install -d ${D}${datadir}/${BPN}
	install -m 0744 ${S}/saa ${D}${datadir}/${BPN}
	pdftotext ${S}/SAA_UserGuide.pdf ${D}${datadir}/${BPN}/SAA_UserGuide.txt
}
