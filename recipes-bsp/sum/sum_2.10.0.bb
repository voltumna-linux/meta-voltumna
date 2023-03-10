DESCRIPTION = "Supermicro Update Manager (SUM) is used for managing and configuring \
the BIOS/BMC firmware for Supermicro X10 generation motherboards and above."
HOMEPAGE = "https://www.supermicro.com/en/solutions/management-software/supermicro-update-manager"
LICENSE = "CLOSED"

COMPATIBLE_HOST = "x86_64.*-linux"

SUFFIX = "Linux_x86_64"
SRC_URI = "https://www.supermicro.com/Bios/sw_download/527/sum_${PV}_${SUFFIX}_20221209.tar.gz"
SRC_URI[sha256sum] = "4f64bde6c60250edb03935f7a8cad3e579e953a6822660b763d8694bfad6ea35"

S = "${WORKDIR}/${BPN}_${PV}_${SUFFIX}"
PACKAGES = "${BPN}"
INSANE_SKIP:${PN} = "already-stripped ldflags debug-files file-rdeps"

do_install() {
	install -d ${D}${datadir}/${BPN}
	install -m 0744 ${S}/sum ${D}${datadir}/${BPN}
	pdftotext ${S}/SUM_UserGuide.pdf ${D}${datadir}/${BPN}/SUM_UserGuide.txt
}
