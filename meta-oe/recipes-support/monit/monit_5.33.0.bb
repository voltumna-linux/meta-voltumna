DESCRIPTION = "Monit is a free open source utility for managing and monitoring, \
processes, programs, files, directories and filesystems on a UNIX system. \
Monit conducts automatic maintenance and repair and can execute meaningful \
causal actions in error situations."

HOMEPAGE = "http://mmonit.com/monit/"

LICENSE = "AGPL-3.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=ea116a7defaf0e93b3bb73b2a34a3f51 \
                    file://libmonit/COPYING;md5=2405f1c59ed1bf3714cebdb40162ce92"

SRC_URI = " \
	https://mmonit.com/monit/dist/monit-${PV}.tar.gz \
	file://monit \
	file://monitrc \
"

SRC_URI[sha256sum] = "1ace889c0183473a9d70160df6533bb6e1338dc1354f5928507803e1e2a863b5"

DEPENDS = "zlib bison-native libnsl2 flex-native openssl virtual/crypt"

inherit autotools-brokensep systemd update-rc.d

PACKAGECONFIG ??= "${@bb.utils.filter('DISTRO_FEATURES', 'pam', d)}"
PACKAGECONFIG[pam] = "--with-pam,--without-pam,libpam"

EXTRA_OECONF = "\
    libmonit_cv_setjmp_available=no \
    libmonit_cv_vsnprintf_c99_conformant=no \
    --with-ssl-lib-dir=${STAGING_LIBDIR} \
    --with-ssl-incl-dir=${STAGING_INCDIR} \
"

SYSTEMD_SERVICE:${PN} = "monit.service"
SYSTEMD_AUTO_ENABLE = "enable"

INITSCRIPT_PACKAGES = "${PN}"
INITSCRIPT_NAME:${PN} = "monit"
INITSCRIPT_PARAMS:${PN} = "defaults 89"

do_configure:prepend() {
    rm -rf ${S}/m4/*
}

do_install:append() {

    # Configuration file
    install -Dm 0600 ${WORKDIR}/monitrc ${D}${sysconfdir}/monitrc

    # SystemD
    install -Dm 0644 ${S}/system/startup/monit.service.in ${D}${systemd_system_unitdir}/monit.service
    sed -i -e 's,@prefix@,${exec_prefix},g' ${D}${systemd_unitdir}/system/monit.service

    # SysV
    install -Dm 0755 ${WORKDIR}/monit ${D}${sysconfdir}/init.d/monit
}
