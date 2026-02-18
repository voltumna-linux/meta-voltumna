DESCRIPTION = "TigerVNC remote display system"
HOMEPAGE = "http://www.tigervnc.com/"
LICENSE = "GPL-2.0-or-later"
SECTION = "x11/utils"
DEPENDS = "xserver-xorg gnutls jpeg libxtst gettext-native fltk libpam"
RDEPENDS:${PN} = "coreutils hicolor-icon-theme perl bash xkbcomp"

LIC_FILES_CHKSUM = "file://LICENCE.TXT;md5=75b02c2872421380bbd47781d2bd75d3"

S = "${WORKDIR}/git"

inherit autotools cmake features_check pkgconfig

REQUIRED_DISTRO_FEATURES = "x11 pam"

B = "${S}"

SRCREV = "540bfc3278e396321124d4b18a798ac2bc18b6ca"

SRC_URI = "git://github.com/TigerVNC/tigervnc.git;branch=1.11-branch;protocol=https \
           file://0002-do-not-build-tests-sub-directory.patch \
           file://0003-add-missing-dynamic-library-to-FLTK_LIBRARIES.patch \
           file://0004-tigervnc-add-fPIC-option-to-COMPILE_FLAGS.patch \
           file://0001-xserver21.1.1.patch-Add-Xorg-21-patch.patch \
           file://0001-xorg-version.h-Increase-supported-Xorg-version-to-1..patch \
           file://0001-xvnc-adapt-for-1.21.patch \
"

# Keep sync with xorg-server in oe-core
XORG_PN ?= "xorg-server"
XORG_PV ?= "21.1.18"
SRC_URI += "${XORG_MIRROR}/individual/xserver/${XORG_PN}-${XORG_PV}.tar.xz;name=xorg"
XORG_S = "${WORKDIR}/${XORG_PN}-${XORG_PV}"
SRC_URI[xorg.md5sum] = "43225ddc1fd8d7ae7671c25ab6d1f927"
SRC_URI[xorg.sha256sum] = "c878d1930d87725d4a5bf498c24f4be8130d5b2646a9fd0f2994deff90116352"

# It is the directory containing the Xorg source for the
# machine on which you are building TigerVNC.
XSERVER_SOURCE_DIR="${S}/unix/xserver"

do_patch[postfuncs] += "do_patch_xserver"
do_patch_xserver () {
    # Put the xserver source in the right place in the tigervnc source tree
    cp -rfl ${XORG_S}/* ${XSERVER_SOURCE_DIR}

    cd ${XSERVER_SOURCE_DIR}
    xserverpatch="${S}/unix/xserver21.patch"
    echo "Apply $xserverpatch"
    patch -p1 -b --suffix .vnc < $xserverpatch
}

EXTRA_OECONF = "--disable-xorg --disable-xnest --disable-xvfb --disable-dmx \
        --disable-xwin --disable-xephyr --disable-kdrive --with-pic \
        --disable-static --disable-xinerama \
        --with-xkb-output=${localstatedir}/lib/xkb \
        --disable-glx --disable-dri --disable-dri2 \
        --disable-config-hal \
        --disable-config-udev \
        --without-dtrace \
        --disable-unit-tests \
        --disable-devel-docs \
        --disable-selective-werror \
        --disable-xshmfence \
        --disable-config-udev \
        --disable-dri3 \
        --disable-libunwind \
        --without-xmlto \
        --enable-systemd-logind=no \
        --disable-xinerama \
        --disable-xwayland \
"

EXTRA_OECMAKE += "${@bb.utils.contains('DISTRO_FEATURES', 'systemd', '-DCMAKE_INSTALL_UNITDIR=${systemd_unitdir}', '-DINSTALL_SYSTEMD_UNITS=OFF', d)}"

do_configure:append () {
    olddir=`pwd`
    cd ${XSERVER_SOURCE_DIR}

    rm -rf aclocal-copy/
    rm -f aclocal.m4

    export ACLOCALDIR="${XSERVER_SOURCE_DIR}/aclocal-copy"
    mkdir -p ${ACLOCALDIR}/
    if [ -d ${STAGING_DATADIR_NATIVE}/aclocal ]; then
        cp-noerror ${STAGING_DATADIR_NATIVE}/aclocal/ ${ACLOCALDIR}/
    fi
    if [ -d ${STAGING_DATADIR}/aclocal -a "${STAGING_DATADIR_NATIVE}/aclocal" != "${STAGING_DATADIR}/aclocal" ]; then
        cp-noerror ${STAGING_DATADIR}/aclocal/ ${ACLOCALDIR}/
    fi
    ACLOCAL="aclocal --system-acdir=${ACLOCALDIR}/" autoreconf -Wcross --verbose --install --force ${EXTRA_AUTORECONF} $acpaths || bbfatal "autoreconf execution failed."
    chmod +x ./configure
    ${CACHED_CONFIGUREVARS} ./configure ${CONFIGUREOPTS} ${EXTRA_OECONF}
    cd $olddir
}

do_compile:append () {
    olddir=`pwd`
    cd ${XSERVER_SOURCE_DIR}

    oe_runmake

    cd $olddir
}

do_install:append() {
    olddir=`pwd`
    cd ${XSERVER_SOURCE_DIR}/hw/vnc

    oe_runmake 'DESTDIR=${D}' install

    cd $olddir
}

FILES:${PN} += " \
    ${libdir}/xorg/modules/extensions \
    ${datadir}/icons \
    ${systemd_unitdir} \
"

FILES:${PN}-dbg += "${libdir}/xorg/modules/extensions/.debug"

# fixed-version: The vulnerable code is not present in the used version (1.11.0)
CVE_CHECK_IGNORE += "CVE-2014-8241"

# fixed-version: The vulnerable code is not present in the used xserver version (21.1.18)
CVE_CHECK_IGNORE += "CVE-2023-6377 CVE-2023-6478 CVE-2025-26594 CVE-2025-26595 \
CVE-2025-26596 CVE-2025-26597 CVE-2025-26598 CVE-2025-26599 CVE-2025-26600 \
CVE-2025-26601 CVE-2024-0408 CVE-2024-0409"
