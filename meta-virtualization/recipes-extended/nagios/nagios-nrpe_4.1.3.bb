require nagios-common.inc

DESCRIPTION = "Nagios Remote Plugin Executor"
HOMEPAGE = "http://www.nagios.com"
SECTION = "console/network"
PRIORITY = "optional"
LICENSE = "GPL-2.0-only"

LIC_FILES_CHKSUM = "file://src/nrpe.c;beginline=1;endline=35;md5=0dadd78599abbc737af81432702e9161"

SRCNAME = "nrpe"

SRC_URI = "https://github.com/NagiosEnterprises/nrpe/releases/download/${SRCNAME}-${PV}/${SRCNAME}-${PV}.tar.gz \
           file://check_nrpe.cfg \
           file://nagios-nrpe.service \
           file://0001-nrpe-ssl.h-guard-ssl_verify_callback_common-declarat.patch \
"

SRC_URI[md5sum] = "92c61b315fd7c51d3cb52b848a9a5821"
SRC_URI[sha256sum] = "5a86dfde6b9732681abcd6ea618984f69781c294b8862a45dfc18afaca99a27a"
SRC_URI[sha1sum] = "b8842c6f6d555deb5ec0359fd49dfcc7952085d6"
SRC_URI[sha384sum] = "81c83ae3713d0baeef5636d7adae47c27c14eeae757e3962c579ac1486856998bc17a6e1a87aff9b290817fbb474ee09"
SRC_URI[sha512sum] = "dc81e2104b7604e6c67a0dc73a3e6449f7e089390a807be7281492b5ab61e13347ed264292e0642798cee4bafc5978d423184e81bbe753343aaa68daea091f7e"

S = "${UNPACKDIR}/${SRCNAME}-${PV}"

inherit autotools-brokensep update-rc.d systemd update-alternatives pkgconfig

SKIP_RECIPE[nagios-nrpe] ?= "${@bb.utils.contains('BBFILE_COLLECTIONS', 'webserver', '', 'Depends on nagios-core which depends on apache2 from meta-webserver which is not included', d)}"

# IP address of server which proxy should connect to
MONITORING_PROXY_SERVER_IP ??= "192.168.7.2"

# IP address of server which agent should connect to
MONITORING_AGENT_SERVER_IP ??= "192.168.7.4"

EXTRA_OECONF += "--with-nrpe-user=${NAGIOS_USER} \
                 --with-nrpe-group=${NAGIOS_GROUP} \
                 ac_cv_lib_wrap_main=no \
                 ac_cv_path_PERL=${bindir}/perl \
"

# Don't pass --with-ssl-inc / --with-ssl-lib explicitly. When either is
# set, configure disables pkg-config probing and falls back to a hardcoded
# library search that bakes `-Wl,-rpath,<dir>` into LDFLAGS (configure.in
# line: `LDFLAGS="$LDFLAGS -L$SSL_LIB_DIR -Wl,-rpath,$SSL_LIB_DIR"`).
# With our sysroot path that lands as a recipe-sysroot RPATH in the
# installed binaries and trips do_package_qa [rpaths] + [buildpaths].
# An empty EXTRA_OECONF_SSL leaves PACKAGECONFIG[ssl] adding nothing to
# OECONF; pkg-config (driven by the openssl DEPENDS) finds the library
# cleanly via the standard --libs flow, which doesn't baked-in rpath.
EXTRA_OECONF_SSL = ""

PACKAGECONFIG[ssl] = "${EXTRA_OECONF_SSL},--disable-ssl,openssl-native openssl,"
PACKAGECONFIG[cmdargs] = "--enable-command-args,--disable-command-args,,"
PACKAGECONFIG[bashcomp] = "--enable-bash-command-substitution,--disable-bash-command-substitution,,"

# SSL enabled by default: v4.1.3 references `use_ssl` outside HAVE_SSL guards
# in check_nrpe.c and nrpe.c, but the symbol is only defined in nrpe-ssl.c
# which configure adds to $(SSL_OBJS) only when --enable-ssl is passed.
# Disabling SSL would also expose the unguarded X509_STORE_CTX declaration
# in include/nrpe-ssl.h (handled by 0001-nrpe-ssl.h-guard-* in case the
# user opts out).
PACKAGECONFIG ??= "cmdargs bashcomp ssl"

do_configure() {
    oe_runconf || die "make failed"
}

do_compile() {
    oe_runmake all
}

do_install:append() {
    oe_runmake 'DESTDIR=${D}' install-daemon
    oe_runmake 'DESTDIR=${D}' install-config

    install -d ${D}${sysconfdir}/init.d
    install -m 755 ${B}/startup/debian-init ${D}${sysconfdir}/init.d/nrpe

    install -d ${D}${NAGIOS_CONF_DIR}/nrpe.d
    echo "include_dir=${NAGIOS_CONF_DIR}/nrpe.d" >> ${D}${NAGIOS_CONF_DIR}/nrpe.cfg

    sed -e "s/^allowed_hosts=.*/allowed_hosts=${MONITORING_AGENT_SERVER_IP}/g" \
        -i ${D}${NAGIOS_CONF_DIR}/nrpe.cfg

    install -d ${D}${NAGIOS_PLUGIN_CONF_DIR}
    install -m 664 ${UNPACKDIR}/check_nrpe.cfg ${D}${NAGIOS_PLUGIN_CONF_DIR}

    if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
        install -d ${D}${systemd_unitdir}/system
        install -m 644 ${UNPACKDIR}/nagios-nrpe.service ${D}${systemd_unitdir}/system/
    fi
}

PACKAGES = "${PN}-dbg ${PN}-plugin ${PN}-daemon"

FILES:${PN}-plugin = "${NAGIOS_PLUGIN_DIR} \
                      ${NAGIOS_PLUGIN_CONF_DIR} \
"

FILES:${PN}-daemon = "${sysconfdir} \
                      ${bindir} \
                      ${nonarch_libdir}/tmpfiles.d/ \
                      ${localstatedir} \
"

RDEPENDS:${PN}-daemon = "nagios-base"
RDEPENDS:${PN}-plugin = "nagios-base"

SYSTEMD_PACKAGES = "${PN}-daemon"
SYSTEMD_SERVICE:${PN}-daemon = "nagios-nrpe.service"
SYSTEMD_AUTO_ENABLE:${PN}-daemon = "enable"

INITSCRIPT_PACKAGES = "${PN}-daemon"
INITSCRIPT_NAME:${PN}-daemon = "nrpe"
INITSCRIPT_PARAMS:${PN}-daemon = "defaults"

ALTERNATIVE:${PN}-daemon = "nagios"
ALTERNATIVE_LINK_NAME[nagios] = "${localstatedir}/nagios"
