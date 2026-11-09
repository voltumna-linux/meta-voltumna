DESCRIPTION = "Jive is a standalone JAVA application designed to browse and edit the static TANGO database."
HOMEPAGE = "https://gitlab.com/tango-controls/jive"
LICENSE = "GPL-3.0-or-later"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/GPL-3.0-or-later;md5=1c76c4cc354acaac30ed4d5eefea7245"

SRC_URI = " \
	https://repo1.maven.org/maven2/org/tango-controls/Jive/${PV}/Jive-${PV}-jar-with-dependencies.jar;unpack=0 \
	file://jive \
"
SRC_URI[sha256sum] = "4678b5894063ad692dc1ca29448b015d8447909e9c7bba7a2f3786d3ddf826a8"

FILES:${PN} = "${SDKPATHNATIVE}"
do_install() {
	install -d ${D}${SDKPATHNATIVE}/usr/share/esrf-jive/ ${D}${SDKPATHNATIVE}/usr/bin
	install -m 0644 ${WORKDIR}/Jive-${PV}*.jar ${D}${SDKPATHNATIVE}/usr/share/esrf-jive/
	install -m 0755 ${WORKDIR}/jive ${D}${SDKPATHNATIVE}/usr/bin
}

inherit nativesdk
