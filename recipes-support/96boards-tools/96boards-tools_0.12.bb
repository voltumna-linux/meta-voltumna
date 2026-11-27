SUMMARY = "Useful bits an pieces to make 96Boards more standard across the board"
HOMEPAGE = "https://github.com/96boards/96boards-tools"
SECTION = "devel"

LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/GPL-2.0-or-later;md5=fed54355545ffd980b814dab4a3b312c"

SRCREV = "52ad42bb74ba4b3fcece2483f0d496494d60715f"
SRC_URI = "git://github.com/96boards/96boards-tools;branch=master;protocol=https \
           "
# PV (0.12) is already ahead of the last upstream tag (0.11) and the recipe
# tracks master: track new commits instead and let devtool update SRCREV.
UPSTREAM_CHECK_COMMITS = "1"

inherit systemd allarch update-rc.d

do_install () {
    install -d ${D}${sysconfdir}/udev/rules.d
    install -m 0644 ${S}/*.rules ${D}${sysconfdir}/udev/rules.d/
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${S}/resize-disk ${D}${sysconfdir}/init.d/

    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${S}/resize-helper.service ${D}${systemd_unitdir}/system

    install -d ${D}${sbindir}
    install -m 0755 ${S}/resize-helper ${D}${sbindir}
}

INITSCRIPT_NAME = "resize-disk"
INITSCRIPT_PARAMS = "start 99 5 2 . stop 20 0 1 6 ."

SYSTEMD_SERVICE:${PN} = "resize-helper.service"
RDEPENDS:${PN} += "e2fsprogs-resize2fs gptfdisk parted util-linux udev"
