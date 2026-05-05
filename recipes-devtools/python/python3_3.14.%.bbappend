FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:class-target = " \
    file://0001-Fix-platform-triplet-mismatch-for-PowerPC-SPE-target.patch \
    file://0002-Fix-termios-build-when-sys-ioctl.h-uses-struct-termi.patch \
    file://0003-Provide-struct-termio-fallback-when-termio.h-sys-ter.patch \
    "
