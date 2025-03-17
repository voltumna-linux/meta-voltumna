SUMMARY = "Intel(R) METEE Library"
DESCRIPTION = "MEETEE library provides a cross-platform simple \
 programing interface for accessing Intel HECI interfaces on devices \
 found in BigCore and Atom based products."

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://COPYING;md5=2ee41112a44fe7014dce33e26468ba93"

COMPATIBLE_HOST = '(i.86|x86_64).*-linux'

inherit cmake

SRC_URI = "git://github.com/intel/metee.git;branch=master;protocol=https"
SRCREV = "0d6f19420bebaa92b0e3dcb6b81e352820f1f1cc"

S = "${WORKDIR}/git"

