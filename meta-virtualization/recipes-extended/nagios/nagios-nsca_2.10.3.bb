require nagios-common.inc

DESCRIPTION = "Nagios Service Check Acceptor"
HOMEPAGE = "http://exchange.nagios.org"
SECTION = "console/network"
PRIORITY = "optional"
LICENSE = "GPL-2.0-only"

LIC_FILES_CHKSUM = "file://src/nsca.c;beginline=1;endline=16;md5=c94838c8194765df77dbf93c7e10b5a2"

SRCNAME = "nsca"

# Upstream development and release artifacts moved to GitHub; the historical
# prdownloads.sourceforge.net path returns 404 for anything past 2.9.2.
SRC_URI = "https://github.com/NagiosEnterprises/${SRCNAME}/releases/download/${SRCNAME}-${PV}/${SRCNAME}-${PV}.tar.gz \
           file://init-script.in \
           file://nagios-nsca.service \
"

SRC_URI[md5sum] = "25048d91910a45213c0f0ea5a8da11c9"
SRC_URI[sha256sum] = "0b36d5c10936f98d278b66c682af95b8e227c5942ad725c4a1949945296f6877"

S = "${UNPACKDIR}/${SRCNAME}-${PV}"

inherit update-rc.d autotools-brokensep systemd dos2unix

SKIP_RECIPE[nagios-nsca] ?= "${@bb.utils.contains('BBFILE_COLLECTIONS', 'webserver', '', 'Rdepends on nagios-base provided by nagios-core which depends on apache2 from meta-webserver which is not included', d)}"

DEPENDS = "libmcrypt"

EXTRA_OECONF += "--with-nsca-user=${NAGIOS_USER} \
                 --with-nsca-grp=${NAGIOS_GROUP} \
                 --with-libmcrypt-prefix=${STAGING_DIR_HOST} \
                 ac_cv_path_LIBMCRYPT_CONFIG=${STAGING_BINDIR_CROSS}/libmcrypt-config \
                 ac_cv_lib_wrap_main=no \
                 ac_cv_path_PERL=${bindir}/perl \
"

do_configure() {
    cp ${UNPACKDIR}/init-script.in ${S}/init-script.in
    oe_runconf || die "make failed"
}

do_install() {
    CONF_DIR=${D}${NAGIOS_CONF_DIR}

    install -d ${CONF_DIR}
    install -d ${D}${sysconfdir}/init.d
    install -d ${D}${bindir}

    install -m 755 ${S}/sample-config/nsca.cfg ${CONF_DIR}
    install -m 755 ${S}/sample-config/send_nsca.cfg ${CONF_DIR}
    install -m 755 ${S}/init-script ${D}${sysconfdir}/init.d/nsca

    install -m 755 ${S}/src/nsca ${D}${bindir}
    install -m 755 ${S}/src/send_nsca ${D}${bindir}

    if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
        install -d ${D}${systemd_unitdir}/system
        install -m 644 ${UNPACKDIR}/nagios-nsca.service ${D}${systemd_unitdir}/system/
    fi
}

PACKAGES = "${PN}-dbg ${PN}-daemon ${PN}-client"

FILES:${PN}-daemon = "${sysconfdir}/init.d \
                      ${NAGIOS_CONF_DIR}/nsca.cfg \
                      ${bindir}/nsca \
"

FILES:${PN}-client = "${NAGIOS_CONF_DIR}/send_nsca.cfg \
                      ${bindir}/send_nsca \
"

RDEPENDS:${PN}-daemon += "libmcrypt \
                          nagios-base \
"
RDEPENDS:${PN}-client += "libmcrypt \
                          nagios-base \
"

SYSTEMD_PACKAGES = "${PN}-daemon"
SYSTEMD_SERVICE:${PN}-daemon = "nagios-nsca.service"
SYSTEMD_AUTO_ENABLE:${PN}-daemon = "enable"

INITSCRIPT_PACKAGES = "${PN}-daemon"
INITSCRIPT_NAME:${PN}-daemon = "nsca"
INITSCRIPT_PARAMS:${PN}-daemon = "defaults"
