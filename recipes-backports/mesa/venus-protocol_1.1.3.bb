SUMMARY = "Venus protocol for virtual Vulkan driver in Mesa"
HOMEPAGE = "https://gitlab.freedesktop.org/virgl/venus-protocol.git"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=b7013365ba3c3420a99e1222b577ecd9"
DEPENDS = "python3-mako-native"

SRC_URI = "git://gitlab.freedesktop.org/virgl/venus-protocol.git;protocol=https;branch=main"
SRCREV = "02c03c815fd07f2237d7f1161bbafcf6a829373c"

inherit meson pkgconfig python3native

BBCLASSEXTEND = "native nativesdk"
