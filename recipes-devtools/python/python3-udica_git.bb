SUMMARY = "A tool for generating SELinux security policies for containers"
HOMEPAGE = "https://github.com/containers/udica"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=1ebbd3e34237af26da5dc08a4e440464"

SRC_URI = "git://github.com/containers/udica;protocol=https;branch=main"

SRCREV = "890847075c8d79ad4ef98dcea4bee0e3db46af30"
PV = "0.2.9+git"

SRC_URI[md5sum] = "9cc5156a2ff6458a8f52114b9bbc0d7e"
SRC_URI[sha256sum] = "3e8bc47534e0ca9331d72c32f2881bb13b93ded0bcdeab3c833fb7cf61c0a9a5"

SKIP_RECIPE[python3-udica] ?= "${@bb.utils.contains('BBFILE_COLLECTIONS', 'selinux', '', 'Depends on libselinux from meta-selinux which is not included', d)}"

RDEPENDS:${PN} += " \
              selinux-python \
              "

inherit setuptools3
