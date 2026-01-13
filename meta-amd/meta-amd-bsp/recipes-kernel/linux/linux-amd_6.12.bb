DESCRIPTION = "AMD common kernel recipe for Linux 6.12.y"

# Determine major version from PREFERRED_VERSION_linux-amd
MAJOR_VERSION := "${@'.'.join((d.getVar('PREFERRED_VERSION_linux-amd') or '').split('.')[:2])}"

python () {
    major = d.getVar("MAJOR_VERSION")

    if major != "6.12":
        raise bb.parse.SkipRecipe("Skipping linux-amd_6.12.bb because major version is %s" % major)
}

require recipes-kernel/linux/linux-yocto.inc

KMACHINE = "common-pc-64"
KMETA = "kernel-meta"
KCONF_BSP_AUDIT_LEVEL = "1"

# Default branch and metadata repo
KBRANCH = "linux-6.12.y"

# Dynamically pick kernel version (if defined)
INTERNAL_KERNEL_VERSION = "${@d.getVar('PREFERRED_VERSION_linux-amd') or '6.12.10'}"

INCFILE = "linux-amd-${INTERNAL_KERNEL_VERSION}.inc"
require ${INCFILE}

SRC_URI = " \
    git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git;protocol=https;name=machine;branch=${KBRANCH}; \
    git://git.yoctoproject.org/yocto-kernel-cache;type=kmeta;name=meta;branch=yocto-6.12;destsuffix=yocto-kmeta \
"

PV = "${INTERNAL_KERNEL_VERSION}"
KERNEL_VERSION_SANITY_SKIP = "1"

# Common configs
require linux-amd.inc

LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"
PR = "r1"
COMPATIBLE_MACHINE = "${MACHINE}"
#COMPATIBLE_MACHINE = "(v3000|siena|turin)"

# Task variable dependencies. Ensures kernel rebuilds when KERNEL_VERSION changes
do_shared_workdir[vardeps] += "INTERNAL_KERNEL_VERSION"
do_kernel_metadata[vardeps] += "INTERNAL_KERNEL_VERSION"
do_fetch[vardeps] += "INTERNAL_KERNEL_VERSION"
do_compile[vardeps] += "INTERNAL_KERNEL_VERSION"
do_install[vardeps] += "INTERNAL_KERNEL_VERSION"
