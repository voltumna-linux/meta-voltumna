DESCRIPTION = "Tucsen SDK Kit for Linux"
HOMEPAGE = "https://www.tucsen.com/download-software/"
LICENSE = "CLOSED"

PREFIX = "Tucam_linux_ubuntu18.04"
RELEASE_DATE = "20210311"

SRC_URI = " \
	https://www.tucsen.com/uploads/${PREFIX}_v${PV}_${RELEASE_DATE}.zip \
	"
SRC_URI[sha256sum] = "8592cef2f81db432f63261701c8a25cb39020749b656906246cb58b02db71ae9"

COMPATIBLE_HOST = "x86_64.*-linux"
S = "${WORKDIR}/libtucam-${PV}"

do_extract_data() {
	unzip ${DL_DIR}/${PREFIX}_v${PV}_${RELEASE_DATE}.zip -d ${S}/
	cd ${S}; tar zxf sdk.tar.gz
}

python do_unpack() {
    bb.build.exec_func('do_extract_data', d)
}

INSANE_SKIP:${PN} += "file-rdeps"

do_install () {
 	install -d ${D}${sysconfdir}/tucam ${D}${sysconfdir}/udev/rules.d \
		${D}${includedir} ${D}${libdir}
 	install -m 0644 ${S}/TUCamSample/sdk/inc/* ${D}${includedir}
 	cp -dR ${S}/sdk/libTUCam.so* ${D}${libdir}
	install -m 0644 ${S}/sdk/tuusb.conf ${D}${sysconfdir}/tucam
	install -m 0644 ${S}/sdk/50-tuusb.rules ${D}${sysconfdir}/udev/rules.d
}

BBCLASSEXTEND = "nativesdk"
