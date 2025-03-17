include qat.inc

#Dual BSD and GPLv2 License
LICENSE = "BSD-3-Clause & GPL-2.0-only & Apache-2.0"
LIC_FILES_CHKSUM = "\
                    file://LICENSE.GPL;md5=751419260aa954499f7abaabaa882bbe \
                    file://LICENSE.BSD;md5=4a6a5cd99f6064d61adad8c6c0bd080f \
                    file://LICENSE.APACHE;md5=c75985e733726beaba57bc5253e96d04 \
                    "

DEPENDS += "boost udev zlib openssl yasm-native"

export SYSROOT = "${RECIPE_SYSROOT}"

SRC_URI = "https://downloadmirror.intel.com/822703/QAT20.L.1.1.50-00003.tar.gz;subdir=qat20 \
           file://0001-qat-fix-for-cross-compilation-issue.patch \
           file://0003-qat-override-CC-LD-AR-only-when-it-is-not-define.patch \
           file://0005-Added-include-dir-path.patch \
           file://0001-usdm_drv-convert-mutex_lock-to-mutex_trylock-to-avio.patch \
           file://build_fix.patch \
           file://qat20-add-install-target-and-add-folder.patch \
           file://qat20-update-KDIR-for-cross-compilation.patch \
           file://qat20-limit-the-use-of-adf_enable-disable_aer.patch \
           file://qat20-remove-empty-function-adf_dev_mm_invalidate_ra.patch \
          "

SRC_URI[sha256sum] = "a505e0807b82e87314d214244dce4c34de477a555e6c95034f150c079c6d1b51"

S = "${WORKDIR}/qat20"
