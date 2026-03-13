DESCRIPTION = "Pogo is the TANGO code generator. It allows to define a TANGO class model."
HOMEPAGE = "https://gitlab.com/tango-controls/pogo"
LICENSE = "GPLv3"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/GPL-3.0;md5=1c76c4cc354acaac30ed4d5eefea7245"

SRC_URI = " \
	https://repo1.maven.org/maven2/org/tango-controls/Pogo/${PV}/Pogo-${PV}.jar;unpack=0 \
	file://pogo \
"
SRC_URI[sha256sum] = "d9bbe5f7cfcf15b42ba0be5c9ae046da99db1362f0fbd3fd9d9f8f4906c29592"

FILES_${PN} += "${SDKPATHNATIVE}"
do_install() {
	install -d ${D}${SDKPATHNATIVE}/usr/share/esrf-pogo/ ${D}${SDKPATHNATIVE}/usr/bin
	install -m 0644 ${WORKDIR}/Pogo-${PV}.jar ${D}${SDKPATHNATIVE}/usr/share/esrf-pogo/
	install -m 0755 ${WORKDIR}/pogo ${D}${SDKPATHNATIVE}/usr/bin
}

inherit nativesdk
