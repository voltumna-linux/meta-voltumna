DESCRIPTION = "Emergent SDK Installer"
HOMEPAGE = "https://emergentvisiontec.com/resources/?tab=ss"
LICENSE = "CLOSED"

VERSION="2.51.01"
SRC_URI = " \
    file://eSDK_2_51_01_eCap_2_11_02_Ubuntu_20_04_5_15_0_x64.zip \
	"
SRC_URI[sha256sum] = "i3de6aef3bc294d67a4f7641126bb13e68f2b8444c63e9351fa7374ff0ea23b66"

COMPATIBLE_HOST = "x86_64.*-linux"

do_extract_data() {
	ar x emergent_camera.deb
	tar Jxf  data.tar.xz -C "${S}"
}

do_unpack[depends] += "unzip-native:do_populate_sysroot xz-native:do_populate_sysroot"
python do_unpack:append() {
    bb.build.exec_func('do_extract_data', d)
}
