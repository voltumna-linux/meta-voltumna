SUMMARY = "FUSE implementation of overlayfs."
DESCRIPTION = "An implementation of overlay+shiftfs in FUSE for rootless \
containers."

LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://COPYING;md5=b234ee4d69f5fce4486a80fdaf4a4263"

SRCREV = "51108ae00fd52e7d9ece7301aaa6f7a699828b58"
SRC_URI = "git://github.com/containers/fuse-overlayfs.git;nobranch=1;protocol=https"

DEPENDS = "fuse3"

inherit autotools pkgconfig
