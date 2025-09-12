SUMMARY = "Snapper is a tool for Linux file system snapshot management"
HOMEPAGE = "https://github.com/openSUSE/snapper"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=751419260aa954499f7abaabaa882bbe"

DEPENDS = "acl boost btrfs-tools dbus e2fsprogs json-c libxml2 lvm2 ncurses zlib"

# Build separation is slightly broken
inherit autotools-brokensep pkgconfig gettext

SRC_URI = "git://github.com/openSUSE/snapper.git;protocol=https;branch=master \
           file://0001-Fix-build-with-boost-1.89.patch \
          "
SRCREV = "4f3d2b2fc58aefa976668cd25b8eac02ba0f85e7"

EXTRA_OECONF += "--disable-zypp"

PACKAGECONFIG ?= "${@bb.utils.filter('DISTRO_FEATURES', 'api-documentation systemd pam', d)}"
PACKAGECONFIG[pam] = "--enable-pam --with-pam-security=${base_libdir}/security, --disable-pam,libpam"
PACKAGECONFIG[systemd] = "--enable-systemd,--disable-systemd"
PACKAGECONFIG[api-documentation] = "--enable-doc,--disable-doc,libxslt-native docbook-xsl-stylesheets-native"

# Avoid HOSTTOOLS path in binaries
export DIFF_BIN = "${bindir}/diff"
export RM_BIN = "${bindir}/rm"
export RMDIR_BIN = "${bindir}/rmdir"
export MKDIR_BIN = "${bindir}/mkdir"
export TOUCH_BIN = "${bindir}/touch"
export CP_BIN = "${bindir}/cp"
export REALPATH_BIN = "${bindir}/realpath"

do_install:append() {
	install -d ${D}${sysconfdir}/sysconfig
	install -m0644 ${S}/data/default-config ${D}${sysconfdir}/sysconfig/snapper
}

FILES:${PN} += "${base_libdir}/security ${nonarch_libdir} ${systemd_system_unitdir} ${datadir}"

# bash is needed for the testsuite
RDEPENDS:${PN} = "bash diffutils util-linux util-linux-mount"
