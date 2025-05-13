DESCRIPTION = "QATzip is a user space library built on top of the Intel QAT user space library, \
to offload the compression and decompression requests to the Intel Chipset Series."

HOMEPAGE = "https://github.com/intel/QATzip"

LICENSE = "BSD-3-Clause & GPL-2.0-only"
LIC_FILES_CHKSUM = "\
                   file://LICENSE;md5=861458cf9e58e46e3ba1978f81134df4 \
                   file://config_file/LICENSE.GPL;md5=751419260aa954499f7abaabaa882bbe \
"
SRC_URI = "git://github.com/intel/QATzip;protocol=https;branch=master \
           file://remove-rpath.patch \
           ${@bb.utils.contains('PREFERRED_PROVIDER_virtual/qat', 'qat17', 'file://qatzip-check-icp_-.h-header-files-in-icp-subfolder.patch', '', d)} \
"

SRCREV = "6d0cfe51892ea6fe93da73326b1d987905e197c8"

DEPENDS += "virtual/qat util-linux-native lz4"

export ICP_ROOT = "${STAGING_DIR_TARGET}/opt/intel/QAT"
export QZ_ROOT = "${S}"

# static library required to compile qzip and test
DISABLE_STATIC = ""

COMPATIBLE_MACHINE = "null"

inherit autotools-brokensep

S = "${WORKDIR}/git"

do_configure:prepend() {
   cd ${S}
   ./autogen.sh
}

do_compile() {
  oe_runmake all
}

do_install:append() {
  install -d ${D}${sysconfdir}/QATzip/conf_file
  cp -r ${S}/config_file/* ${D}${sysconfdir}/QATzip/conf_file
}
