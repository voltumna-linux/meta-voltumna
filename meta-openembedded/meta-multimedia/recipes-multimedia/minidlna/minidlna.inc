DESCRIPTION = "MiniDLNA (aka ReadyDLNA) is server software with the aim of \
being fully compliant with DLNA/UPnP-AV clients."
LICENSE = "GPL-2.0-only|BSD-3-Clause"
DEPENDS = "ffmpeg flac libav jpeg sqlite3 libexif libogg libid3tag libvorbis"

# because it depends on libav which has commercial flag
LICENSE_FLAGS = "commercial"

inherit gettext autotools-brokensep update-rc.d systemd

SRC_URI = "git://git.code.sf.net/p/minidlna/git;branch=master;module=git \
           file://minidlna-daemon.init.d \
           file://minidlna.service \
           file://0001-configure-Check-for-clock_gettime-seprately-from-__N.patch \
           file://0001-Add-compatibility-with-FFMPEG-7.0.patch \
           "


# This remove "--exclude=autopoint" option from autoreconf argument to avoid
# configure.ac:30: error: required file './ABOUT-NLS' not found
EXTRA_AUTORECONF = ""

# Reproducibility: force os-name and os-version to constants to avoid host
# related build differences
EXTRA_OECONF = "--with-os-name='${DISTRO_NAME}' --with-os-version=''"

do_install:append(){
    install -d ${D}${sysconfdir}
    install -m 0755 minidlna.conf ${D}${sysconfdir}

# Systemd script
    install -d ${D}${nonarch_base_libdir}/systemd/system
    install -m 0755 ${UNPACKDIR}/minidlna.service ${D}${nonarch_base_libdir}/systemd/system

# Sysvinit script
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${UNPACKDIR}/minidlna-daemon.init.d ${D}${sysconfdir}/init.d/minidlna

}

SYSTEMD_SERVICE:${PN} = "minidlna.service"

INITSCRIPT_NAME = "minidlna"
INITSCRIPT_PARAMS = "defaults 90"

