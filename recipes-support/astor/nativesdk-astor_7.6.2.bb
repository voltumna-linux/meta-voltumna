DESCRIPTION = "Astor is a graphical Tango control system administration tool."
HOMEPAGE = "https://gitlab.com/tango-controls/astor"
LICENSE = "GPL-3.0-or-later"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/GPL-3.0-or-later;md5=1c76c4cc354acaac30ed4d5eefea7245"

SRC_URI = " \
	https://repo1.maven.org/maven2/org/tango-controls/Astor/${PV}/Astor-${PV}-jar-with-dependencies.jar;unpack=0 \
	file://astor \
"
SRC_URI[sha256sum] = "7a4bda4f324e3df7752ae513a318129e219de629579333ab633a53e1a1c1dda0"

FILES:${PN} += "${SDKPATHNATIVE}"
do_install() {
	install -d ${D}${SDKPATHNATIVE}/usr/share/esrf-astor/ ${D}${SDKPATHNATIVE}/usr/bin
	install -m 0644 ${WORKDIR}/Astor-${PV}*.jar ${D}${SDKPATHNATIVE}/usr/share/esrf-astor/
	install -m 0755 ${WORKDIR}/astor ${D}${SDKPATHNATIVE}/usr/bin
}

inherit nativesdk
