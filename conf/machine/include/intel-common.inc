require conf/machine/include/meta-intel.inc
require conf/machine/include/x86/x86-base.inc

MACHINE_FEATURES += "efi"
MACHINE_FEATURES += "intel-ucode"

MACHINE_HWCODECS ?= "intel-media-driver intel-mediasdk intel-vaapi-driver gstreamer1.0-vaapi"

# Enable optional dpdk:
COMPATIBLE_MACHINE:pn-dpdk = "intel-corei7-64"

# Enable optional QAT items:
COMPATIBLE_MACHINE:pn-qat16 = "intel-corei7-64"
COMPATIBLE_MACHINE:pn-qat17 = "intel-corei7-64"
COMPATIBLE_MACHINE:pn-zlib-qat = "intel-corei7-64"

XSERVER ?= "${XSERVER_X86_BASE} \
            ${XSERVER_X86_EXT} \
            ${XSERVER_X86_FBDEV} \
            ${XSERVER_X86_I915} \
            ${XSERVER_X86_I965} \
            ${XSERVER_X86_MODESETTING} \
            ${XSERVER_X86_VESA} \
            ${XSERVER_X86_ASPEED_AST} \
           "

IMAGE_FSTYPES += "wic"
WKS_FILE ?= "grub-bootdisk.wks"
WKS_FILE_DEPENDS:append = " intel-microcode"

KMACHINE = "intel-corei7-64"
ALLOW_EMPTY:${KERNEL_PACKAGE_NAME}-devicetree = "1"
MACHINEOVERRIDES =. "intel-corei7-64:"

EFI_PROVIDER = ""
