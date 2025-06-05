DESCRIPTION = "Emergent SDK Installer"
HOMEPAGE = "https://emergentvisiontec.com/resources/?tab=ss"
LICENSE = "CLOSED"

VERSION="2.27.4"
BUILDNUMBER="20608"
SRC_URI = " \
        https://www.elettra.eu/images/Documents/Voltumna/intranet/predownloaded-tarballs/esdk-installer_${VERSION}.${BUILDNUMBER}.zip \
	file://Porting-from-5.3-to-5.4.patch \
	"
SRC_URI[sha256sum] = "4c508e695d2b6562b917e324a531173172d2208674eb852148757d080ee71a78"

COMPATIBLE_HOST = "x86_64.*-linux"

do_extract_data() {
	tar zxf emergent_camera_${VERSION}.${BUILDNUMBER}-ubuntu18.04.4.x64.tgz 
	ar x emergent_camera.deb
	tar Jxf  data.tar.xz -C "${S}"
}

do_unpack[depends] += "unzip-native:do_populate_sysroot xz-native:do_populate_sysroot"
python do_unpack_append() {
    bb.build.exec_func('do_extract_data', d)
}
