SUMMARY = "Diod is a user space server for the kernel v9fs client."
DESCRIPTION = "\
Diod is a user space server for the kernel v9fs client (9p.ko, 9pnet.ko). \
Although the kernel client supports several 9P variants, diod only supports \
9P2000.L, and only in its feature-complete form, as it appeared in 2.6.38."
SECTION = "console/network"

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=59530bdf33659b29e73d4adb9f9f6552"

PV = "1.1.0+git"
SRCREV = "a8c55f0dd3ad9debc0e77b29ebde6e991d99d55d"
SRC_URI = "git://github.com/chaos/diod.git;protocol=https;branch=master \
           file://diod \
           file://diod.conf \
           file://0001-build-Find-lua-with-pkg-config.patch \
           "
DEPENDS = "libcap ncurses lua"

EXTRA_OECONF = "--disable-auth \
                --with-systemdsystemunitdir=${systemd_unitdir}/system"

# GCC 15 is stricter about const qualifiers; upstream uses -Werror
CFLAGS += "-Wno-error=discarded-qualifiers"

inherit autotools pkgconfig systemd

do_install:append () {
        # install our init based on start-stop-daemon
        install -D -m 0755 ${UNPACKDIR}/diod ${D}${sysconfdir}/init.d/diod
        # install a real(not commented) configuration file for diod
        install -m 0644 ${UNPACKDIR}/diod.conf ${D}${sysconfdir}/diod.conf
}

FILES:${PN} += "${systemd_unitdir}"
