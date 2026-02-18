# Copyright (C) 2010-2012 O.S. Systems Software Ltda. All Rights Reserved
# Released under the MIT license

DESCRIPTION = "FreeRDP RDP client & server library"
HOMEPAGE = "http://www.freerdp.com"
DEPENDS = "openssl alsa-lib libusb1"
SECTION = "net"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3b83ef96387f14655fc854ddc3c6bd57"

inherit pkgconfig cmake gitpkgv ptest

RDEPENDS:${PN}-ptest += "coreutils pcsc-lite-lib" 

PE = "1"
PKGV = "${GITPKGVTAG}"

SRCREV = "658a72980f6e93241d927c46cfa664bf2547b8b1"
SRC_URI = "git://github.com/FreeRDP/FreeRDP.git;branch=stable-2.0;protocol=https \
           file://run-ptest \
           file://winpr-makecert-Build-with-install-RPATH.patch \
           file://CVE-2022-39316.patch \
           file://CVE-2022-39318-39319.patch \
           file://CVE-2022-24883.patch \
           file://CVE-2022-39282.patch \
           file://CVE-2022-39320.patch \
           file://CVE-2023-39350.patch \
           file://CVE-2023-39351.patch \
           file://CVE-2023-39352.patch \
           file://CVE-2023-39353.patch \
           file://CVE-2023-40181.patch \
           file://CVE-2023-40569.patch \
           file://CVE-2023-40589.patch \
           file://CVE-2024-22211.patch \
           file://CVE-2024-32039.patch \
           file://CVE-2024-32040.patch \
           file://CVE-2024-32458.patch \
           file://CVE-2024-32459.patch \
           file://CVE-2024-32460.patch \
           file://CVE-2024-32658.patch \
           "

S = "${WORKDIR}/git"

EXTRA_OECMAKE += " \
    -DWITH_ALSA=ON \
    -DWITH_FFMPEG=OFF \
    -DWITH_CUNIT=OFF \
    -DWITH_NEON=OFF \
    -DBUILD_STATIC_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDANT_CODE=ON \
    -DWITH_MANPAGES=OFF \
"

PACKAGECONFIG ??= " \
    ${@bb.utils.filter('DISTRO_FEATURES', 'directfb pam pulseaudio wayland x11', d)}\
    ${@bb.utils.contains('PTEST_ENABLED', '1', 'test', '', d)} \
    gstreamer cups pcsc \
"

X11_DEPS = "virtual/libx11 libxinerama libxext libxcursor libxv libxi libxrender libxfixes libxdamage libxrandr libxkbfile"
PACKAGECONFIG[x11] = "-DWITH_X11=ON -DWITH_XINERAMA=ON -DWITH_XEXT=ON -DWITH_XCURSOR=ON -DWITH_XV=ON -DWITH_XI=ON -DWITH_XRENDER=ON -DWITH_XFIXES=ON -DWITH_XDAMAGE=ON -DWITH_XRANDR=ON -DWITH_XKBFILE=ON,-DWITH_X11=OFF,${X11_DEPS}"
PACKAGECONFIG[wayland] = "-DWITH_WAYLAND=ON,-DWITH_WAYLAND=OFF,wayland wayland-native libxkbcommon"
PACKAGECONFIG[directfb] = "-DWITH_DIRECTFB=ON,-DWITH_DIRECTFB=OFF,directfb"
PACKAGECONFIG[pam] = "-DWITH_PAM=ON,-DWITH_PAM=OFF,libpam"
PACKAGECONFIG[pcsc] = "-DWITH_PCSC=ON,-DWITH_PCSC=OFF,pcsc-lite"
PACKAGECONFIG[pulseaudio] = "-DWITH_PULSEAUDIO=ON,-DWITH_PULSEAUDIO=OFF,pulseaudio"
PACKAGECONFIG[gstreamer] = "-DWITH_GSTREAMER_1_0=ON,-DWITH_GSTREAMER_1_0=OFF,gstreamer1.0 gstreamer1.0-plugins-base"
PACKAGECONFIG[cups] = "-DWITH_CUPS=ON,-DWITH_CUPS=OFF,cups"
PACKAGECONFIG[test] = "-DBUILD_TESTING=ON,-DBUILD_TESTING=OFF"

PACKAGES =+ "libfreerdp"

LEAD_SONAME = "libfreerdp.so"
FILES:libfreerdp = "${libdir}/lib*${SOLIBS}"

PACKAGES_DYNAMIC += "^libfreerdp-plugin-.*"

do_configure:prepend() {
    if ${@bb.utils.contains('PTEST_ENABLED', '1', 'true', 'false', d)}; then
        sed -i 's,CMAKE_CURRENT_SOURCE_DIR,"${PTEST_PATH}/test_data",' ${S}/libfreerdp/codec/test/TestFreeRDPCodecProgressive.c
        sed -i 's,\${CMAKE_CURRENT_SOURCE_DIR},"${PTEST_PATH}/test_data",' ${S}/libfreerdp/crypto/test/CMakeLists.txt
        sed -i 's,\${CMAKE_CURRENT_SOURCE_DIR},${PTEST_PATH}/test_data,' ${S}/winpr/libwinpr/utils/test/CMakeLists.txt
    fi
}

# we will need winpr-makecert to generate TLS certificates
do_install:append () {
    install -d ${D}${bindir}
    install -m755 winpr/tools/makecert-cli/winpr-makecert ${D}${bindir}
    rm -rf ${D}${libdir}/cmake
    rm -rf ${D}${libdir}/freerdp
}

do_install_ptest() {
    install -d ${D}${PTEST_PATH}/test_data
    cp -r ${B}/Testing ${D}${PTEST_PATH}
    install -m 0644 ${S}/libfreerdp/codec/test/progressive.bmp ${D}${PTEST_PATH}/test_data/
    install -m 0644 ${S}/libfreerdp/crypto/test/Test_x509_cert_info.pem ${D}${PTEST_PATH}/test_data/
    install -m 0644 ${S}/winpr/libwinpr/utils/test/lodepng_32bit.png ${D}${PTEST_PATH}/test_data/
    install -m 0644 ${S}/winpr/libwinpr/utils/test/lodepng_32bit.bmp ${D}${PTEST_PATH}/test_data/
}

python populate_packages:prepend () {
    freerdp_root = d.expand('${libdir}/freerdp')

    do_split_packages(d, freerdp_root, r'^(audin_.*)\.so$',
        output_pattern='libfreerdp-plugin-%s',
        description='FreeRDP plugin %s',
        prepend=True, extra_depends='libfreerdp-plugin-audin')

    do_split_packages(d, freerdp_root, r'^(rdpsnd_.*)\.so$',
        output_pattern='libfreerdp-plugin-%s',
        description='FreeRDP plugin %s',
        prepend=True, extra_depends='libfreerdp-plugin-rdpsnd')

    do_split_packages(d, freerdp_root, r'^(tsmf_.*)\.so$',
        output_pattern='libfreerdp-plugin-%s',
        description='FreeRDP plugin %s',
        prepend=True, extra_depends='libfreerdp-plugin-tsmf')

    do_split_packages(d, freerdp_root, r'^([^-]*)\.so$',
        output_pattern='libfreerdp-plugin-%s',
        description='FreeRDP plugin %s',
        prepend=True, extra_depends='')
}
