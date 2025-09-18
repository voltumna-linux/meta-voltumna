# Install EDK2 Base Tools in native sysroot. Currently the BaseTools are not
# built, they are just copied to native sysroot. This is sufficient for
# generating UEFI capsules as it only depends on some python scripts. Other
# tools need to be built first before adding to sysroot.

SUMMARY = "EDK2 Base Tools"
LICENSE = "BSD-2-Clause-Patent"

# EDK2
SRC_URI = "git://github.com/tianocore/edk2.git;branch=master;protocol=https"
LIC_FILES_CHKSUM = "file://License.txt;md5=2b415520383f7964e96700ae12b4570a"

SRCREV = "d46aa46c8361194521391aa581593e556c707c6e"

UPSTREAM_CHECK_GITTAGREGEX = "^edk2-stable(?P<pver>\d+)$"

inherit native

RDEPENDS:${PN} += "python3-core"

do_install () {
    mkdir -p ${D}${bindir}/edk2-BaseTools
    cp -r ${S}/BaseTools/* ${D}${bindir}/edk2-BaseTools/
}
