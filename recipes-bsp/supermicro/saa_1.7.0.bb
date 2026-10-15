DESCRIPTION = "SuperServer Automation Assistant (SAA) is the powerful CLI \
(Command-Line Interface) based utility that eases the management effort \
for IT Administrator to easily deploy, configure, and update the managed \
systems from single node to datacenter scale."
HOMEPAGE = "https://www.supermicro.com/en/solutions/management-software/superserver-automation-assistant"
LICENSE = "LicenseRef-saa-CLOSED"
LIC_FILES_CHKSUM = "file://SAA_UserGuide.pdf;md5=b30a5bdb1d4693e37b22ff9277a9c8c5"

COMPATIBLE_HOST = "x86_64.*-linux"

DIR = "1182"
SUFFIX = "Linux_x86_64"
DATE = "20260910"
SRC_URI = "https://www.supermicro.com/Bios/sw_download/${DIR}/saa_${PV}_${SUFFIX}_${DATE}.tar.gz"
SRC_URI[sha256sum] = "b37cad4e9e4388451c551ef2ad37309958ce2c5e7d9153fd804abb8e6d983c6f"

S = "${UNPACKDIR}/${BPN}_${PV}_${SUFFIX}"
PACKAGES = "${BPN}"
INSANE_SKIP:${PN} = "already-stripped ldflags debug-files file-rdeps"

do_install() {
	install -d ${D}${datadir}/${BPN} ${D}${datadir}/${BPN}/acpica_bin/
	install -m 0744 ${S}/saa ${D}${datadir}/${BPN}
        install -m 0744 ${S}/acpica_bin/* ${D}${datadir}/${BPN}/acpica_bin/
	pdftotext ${S}/SAA_UserGuide.pdf ${D}${datadir}/${BPN}/SAA_UserGuide.txt
}
