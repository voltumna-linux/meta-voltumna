DESCRIPTION = "Astor is a graphical Tango control system administration tool."
HOMEPAGE = "https://gitlab.com/tango-controls/astor"
LICENSE = "GPLv3"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/GPL-3.0;md5=c79ff39f19dfec6d293b95dea7b07891"

SRC_URI = " \
	https://repo1.maven.org/maven2/org/tango-controls/Astor/${PV}/Astor-${PV}-jar-with-dependencies.jar;unpack=0 \
	file://astor \
"
SRC_URI[sha256sum] = "ceb4767fe51a4be6026330eded1233d14c1b49abab6d52030a99875dc995d544"

FILES_${PN} += "${SDKPATHNATIVE}"
do_install() {
	install -d ${D}${SDKPATHNATIVE}/usr/share/esrf-astor/ ${D}${SDKPATHNATIVE}/usr/bin
	install -m 0644 ${WORKDIR}/Astor-${PV}*.jar ${D}${SDKPATHNATIVE}/usr/share/esrf-astor/
	install -m 0755 ${WORKDIR}/astor ${D}${SDKPATHNATIVE}/usr/bin
}

inherit nativesdk
