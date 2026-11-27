DESCRIPTION = "Beckhoff protocol to communicate with TwinCAT devices."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=b20289b0f8d3f1fde00abc1e1dba20ab"

SRC_URI = " \
    git://github.com/Beckhoff/ADS.git;protocol=https;branch=master \
    file://add_soname_version.patch \
    "
SRCREV = "67886519fcec58546be316b3846b1edcb2c829f5"

# Tags are MAJOR.MINOR.PATCH-N (the -N suffix is not part of the recipe
# version); the old vN and vN.M tags do not match the three component pattern.
# The trailing ^{} also matches the peeled entry of annotated tags so that
# devtool picks their commit as the new SRCREV.
UPSTREAM_CHECK_GITTAGREGEX = "^(v)?(?P<pver>\d+\.\d+\.\d+)(-\d+)?(\^\{\})?$"

PACKAGES =+ "${PN}-bin"
do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/adstool ${D}${bindir}
}

inherit meson

BBCLASSEXTEND = "nativesdk"
