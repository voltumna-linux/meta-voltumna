DESCRIPTION = "A python library for manipulating kickstart files"
HOMEPAGE = "https://fedoraproject.org/wiki/pykickstart"
LICENSE = "GPL-2.0-or-later"

LIC_FILES_CHKSUM = "file://COPYING;md5=8ca43cbc842c2336e835926c2166c28b"

inherit python_setuptools_build_meta

RDEPENDS:${PN} = "python3 \
                  python3-requests \
                  python3-six \
"

SRC_URI = "git://github.com/rhinstaller/pykickstart.git;protocol=https;branch=master \
           file://0001-support-authentication-for-kickstart.patch \
           file://0002-pykickstart-parser.py-add-lock-for-readKickstart-and.patch \
           file://0003-comment-out-sections-shutdown-and-environment-in-gen.patch \
           file://0004-load.py-retry-to-invoke-request-with-timeout.patch \
           file://0005-options-adjust-to-behavior-change-in-upstream-_parse.patch \
           "
SRCREV = "fa6c80c0e5c6bee29d089899a10d26e6f7f8afd8"

UPSTREAM_CHECK_GITTAGREGEX = "r(?P<pver>\d+(\.\d+)+(-\d+)*)"

S = "${WORKDIR}/git"
