DESCRIPTION = "Jive is a standalone JAVA application designed to browse and edit the static TANGO database."
HOMEPAGE = "https://gitlab.com/tango-controls/jive"
LICENSE = "GPL-3.0-or-later"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/GPL-3.0-or-later;md5=1c76c4cc354acaac30ed4d5eefea7245"

SRC_URI = " \
	https://repo1.maven.org/maven2/org/tango-controls/Jive/${PV}/Jive-${PV}-jar-with-dependencies.jar;unpack=0 \
	file://jive \
"
SRC_URI[sha256sum] = "5b4c4d1e92b09dff88fc29b0582b3820ec281a547e984e358260f367f5d9cfcc"

FILES:${PN} = "${SDKPATHNATIVE}"
do_install() {
	install -d ${D}${SDKPATHNATIVE}/usr/share/esrf-jive/ ${D}${SDKPATHNATIVE}/usr/bin
	install -m 0644 ${WORKDIR}/Jive-${PV}*.jar ${D}${SDKPATHNATIVE}/usr/share/esrf-jive/
	install -m 0755 ${WORKDIR}/jive ${D}${SDKPATHNATIVE}/usr/bin
}

inherit nativesdk
