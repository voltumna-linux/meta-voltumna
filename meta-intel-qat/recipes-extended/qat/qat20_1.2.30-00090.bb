include qat.inc

#Dual BSD and GPLv2 License
LICENSE = "BSD-3-Clause & GPL-2.0-only & Apache-2.0"
LIC_FILES_CHKSUM = "\
                    file://LICENSE.GPL;md5=751419260aa954499f7abaabaa882bbe \
                    file://LICENSE.BSD;md5=7e3723742f05cc28b730c136742b3b80 \
                    file://LICENSE.APACHE;md5=c75985e733726beaba57bc5253e96d04 \
                    "

DEPENDS += "boost udev zlib openssl yasm-native"

export SYSROOT = "${RECIPE_SYSROOT}"

FILESEXTRAPATHS:prepend := "${THISDIR}/files/qat20:"

SRC_URI = "https://downloadmirror.intel.com/852759/QAT20.L.1.2.30-00090.tar.gz;subdir=qat20 \
           file://qat20-qat-fix-for-cross-compilation-issue.patch \
           file://qat20-Added-include-dir-path.patch \
           file://qat20-add-install-target-and-add-folder.patch \
           file://qat20-update-KDIR-for-cross-compilation.patch \
           file://qat20-qat-override-CC-LD-AR-only-when-it-is-not-define.patch \
           file://0001-usdm_drv-convert-mutex_lock-to-mutex_trylock-to-avio.patch \
          "

SRC_URI[sha256sum] = "a30450052b67457e9a8eea902ee9057a883d72eb92ef45d6fe58694c50dbf807"

S = "${WORKDIR}/qat20"
