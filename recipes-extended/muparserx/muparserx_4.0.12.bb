SUMMARY = "muparserx - A C++ Library for Parsing Expressions with Strings, Complex Numbers, Vectors, Matrices and more."
HOMEPAGE = "https://github.com/beltoforion/muparserx"
SECTION = "libs"
LICENSE = "BSD-2-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=16bfcfd353866012957fa7bfc4ce1307"

SRC_URI = "git://github.com/beltoforion/muparserx.git;protocol=https;branch=master"

SRCREV = "e1bdc2947e71ec8b30891749c1d807a3335ebd6d"

# Tags are vMAJOR.MINOR.PATCH on master. The trailing ^{} also matches the
# peeled entry of annotated tags so that devtool picks their commit as the new
# SRCREV.
UPSTREAM_CHECK_GITTAGREGEX = "^v(?P<pver>\d+(\.\d+)+)(\^\{\})?$"

EXTRA_OECMAKE = " \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DBUILD_SHARED_LIBS=ON \
    "

inherit cmake

BBCLASSEXTEND = "nativesdk"
