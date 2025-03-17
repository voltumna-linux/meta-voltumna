include qat.inc

#Dual BSD and GPLv2 License
LICENSE = "BSD-3-Clause & GPL-2.0-only"
LIC_FILES_CHKSUM = "\
                    file://LICENSE.GPL;md5=751419260aa954499f7abaabaa882bbe \
                    file://LICENSE.BSD;md5=7e3723742f05cc28b730c136742b3b80 \
                    "

DEPENDS += "boost udev zlib openssl nasm-native"

SRC_URI = "https://downloadmirror.intel.com/795697/QAT.L.4.24.0-00005.tar.gz;subdir=qat17 \
           file://0001-qat-fix-for-cross-compilation-issue.patch \
           file://0002-qat-remove-local-path-from-makefile.patch \
           file://0003-qat-override-CC-LD-AR-only-when-it-is-not-define.patch \
           file://0004-update-KDIR-for-cross-compilation.patch \
           file://0005-Added-include-dir-path.patch \
           file://0006-qat-add-install-target-and-add-folder.patch \
           file://0001-usdm_drv-convert-mutex_lock-to-mutex_trylock-to-avio.patch \
           file://qat-remove-the-deprecated-pci-dma-compat.h-API.patch \
           file://fix-redefinition-of-crypto_request_complete.patch \
           file://build_fix.patch \
          "

SRC_URI[sha256sum] = "d32546a312828ef0450ddb1543905b06880aa1eb46a8f3fad71a60292052292b"

S = "${WORKDIR}/qat17"

do_install:append() {
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

