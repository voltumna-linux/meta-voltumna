SUMMARY = "Utility for IPMI control"
DESCRIPTION = "This package contains a utility for interfacing with devices that support \
the Intelligent Platform Management Interface specification. IPMI is \
an open standard for machine health, inventory, and remote power control. \
\
This utility can communicate with IPMI-enabled devices through either a \
kernel driver such as OpenIPMI or over the RMCP LAN protocol defined in \
the IPMI specification. IPMIv2 adds support for encrypted LAN \
communications and remote Serial-over-LAN functionality. \
\
It provides commands for reading the Sensor Data Repository (SDR) and \
displaying sensor values, displaying the contents of the System Event \
Log (SEL), printing Field Replaceable Unit (FRU) information, reading and \
setting LAN configuration, and chassis power control. \
"

HOMEPAGE = "http://codeberg.org/IPMITool/ipmitool"
SECTION = "kernel/userland"

LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://COPYING;md5=9aa91e13d644326bf281924212862184"

DEPENDS = "openssl readline ncurses"
SRCREV = "bf774149ae7f74c12164a5b021b23520c5ca4016"
SRC_URI = "git://codeberg.org/ipmitool/ipmitool;protocol=https;branch=master \
           ${IANA_ENTERPRISE_NUMBERS} \
           file://0001-csv-revision-Drop-the-git-revision-info.patch \
           "

UPSTREAM_CHECK_GITTAGREGEX = "IPMITOOL_(?P<pver>\d+(_\d+)+)"

IANA_ENTERPRISE_NUMBERS ?= ""

# Add these via bbappend if this database is needed by the system
#IANA_ENTERPRISE_NUMBERS = "http://www.iana.org/assignments/enterprise-numbers.txt;name=iana-enterprise-numbers;downloadfilename=iana-enterprise-numbers"
#SRC_URI[iana-enterprise-numbers.sha256sum] = "cdd97fc08325667434b805eb589104ae63f7a9eb720ecea73cb55110b383934c"


inherit autotools pkgconfig

do_install:append() {
        if [ -e ${UNPACKDIR}/iana-enterprise-numbers ]; then
                install -Dm 0755 ${UNPACKDIR}/iana-enterprise-numbers ${D}${datadir}/misc/enterprise-numbers
        fi
}

PACKAGES =+ "${PN}-ipmievd"
FILES:${PN}-ipmievd += "${sbindir}/ipmievd"
FILES:${PN} += "${datadir}/misc"

# --disable-dependency-tracking speeds up the build
# --enable-file-security adds some security checks
# --disable-intf-free disables FreeIPMI support - we don't want to depend on
#   FreeIPMI libraries, FreeIPMI has its own ipmitoool-like utility.
# --disable-registry-download prevents the IANA numbers from being fetched
#   at build time, as it is not repeatable.
#
EXTRA_OECONF = "--disable-dependency-tracking --enable-file-security --disable-intf-free \
                --disable-registry-download \
                "

# http://errors.yoctoproject.org/Errors/Details/766896/
# git/lib/ipmi_fru.c:1556:41: error: initialization of 'struct fru_multirec_mgmt *' from incompatible pointer type 'struct fru_multirect_mgmt *' [-Wincompatible-pointer-types]
CFLAGS += "-Wno-error=incompatible-pointer-types"
