include qat.inc

#Dual BSD and GPLv2 License
LICENSE = "BSD-3-Clause & GPL-2.0-only"
LIC_FILES_CHKSUM = "\
                    file://LICENSE.GPL;md5=751419260aa954499f7abaabaa882bbe \
                    file://LICENSE.BSD;md5=f2e710964f2b777f4dcf2e1ca7e07ecb \
                    "

DEPENDS += "boost udev zlib openssl nasm-native"

FILESEXTRAPATHS:prepend := "${THISDIR}/files/qat17:"

SRC_URI = "https://downloadmirror.intel.com/852035/QAT.L.4.28.0-00004.tar.gz;subdir=qat17 \
           file://qat17-qat-fix-for-cross-compilation-issue.patch \
           file://qat17-update-KDIR-for-cross-compilation.patch \
           file://qat17-Added-include-dir-path.patch \
           file://qat17-qat-add-install-target-and-add-folder.patch \
           file://qat17-qat-remove-local-path-from-makefile.patch \
           file://0001-usdm_drv-convert-mutex_lock-to-mutex_trylock-to-avio.patch \
          "


SRC_URI[sha256sum] = "0ac77429774c6571cff48cc6ddb0d1a44b2696612ddc89e9f5c563d0350eb716"

S = "${UNPACKDIR}/qat17"

do_install:append() {
  install -d ${D}${QAT_HEADER_FILES}/include/icp
  install -m 0644 ${S}/quickassist/include/icp/*.h  ${D}${QAT_HEADER_FILES}/include/icp

  install -D -m 0644 ${S}/quickassist/lookaside/access_layer/src/qat_direct/src/libadf_user.a ${D}${base_libdir}/libadf.a

  install -m 0644 ${S}/quickassist/qat/fw/qat_d15xx.bin  ${D}${nonarch_base_libdir}/firmware
  install -m 0644 ${S}/quickassist/qat/fw/qat_d15xx_mmp.bin  ${D}${nonarch_base_libdir}/firmware

  # ICE-D LCC
  install -m 0644 ${S}/quickassist/qat/fw/qat_200xx.bin  ${D}${nonarch_base_libdir}/firmware
  install -m 0644 ${S}/quickassist/qat/fw/qat_200xx_mmp.bin  ${D}${nonarch_base_libdir}/firmware

  # ICE-D HCC
  install -m 0644 ${S}/quickassist/qat/fw/qat_c4xxx.bin ${D}${nonarch_base_libdir}/firmware
  install -m 0644 ${S}/quickassist/qat/fw/qat_c4xxx_mmp.bin ${D}${nonarch_base_libdir}/firmware
}

