include runc.inc

SRCREV = "e1c1378fc924f56ce53f4547b7204e2beda7dbf0"
SRC_URI = " \
    git://github.com/opencontainers/runc;branch=release-1.5;protocol=https;destsuffix=${GO_SRCURI_DESTSUFFIX} \
    file://0001-Makefile-respect-GOBUILDFLAGS-for-runc-and-remove-re.patch \
    file://CVE-2026-41579.patch \
    "
RUNC_VERSION = "1.5.0-rc.1"

# for compatibility with existing RDEPENDS that have existed since
# runc-docker and runc-opencontainers were separate
RPROVIDES:${PN} += "runc-docker"
RPROVIDES:${PN} += "runc-opencontainers"

CVE_PRODUCT = "runc"

LDFLAGS += "${@bb.utils.contains('DISTRO_FEATURES', 'ld-is-gold', ' -fuse-ld=bfd', '', d)}"
