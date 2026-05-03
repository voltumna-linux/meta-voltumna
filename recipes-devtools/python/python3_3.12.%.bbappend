FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:class-target = " \
    file://0001-Fix-platform-triplet-mismatch-for-PowerPC-SPE-target.patch \
    "
