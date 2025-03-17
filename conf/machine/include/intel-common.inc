require conf/machine/include/meta-intel.inc
require conf/machine/include/x86-base.inc

MACHINE_FEATURES += "efi"
# MACHINE_FEATURES += "wifi 3g nfc"
MACHINE_FEATURES += "intel-ucode"

MACHINE_HWCODECS ?= "intel-media-driver intel-mediasdk intel-vaapi-driver gstreamer1.0-vaapi"

# Enable optional dpdk:
COMPATIBLE_MACHINE_pn-dpdk = "intel-corei7-64"

# Enable optional QAT items:
COMPATIBLE_MACHINE_pn-qat16 = "intel-corei7-64"
COMPATIBLE_MACHINE_pn-qat17 = "intel-corei7-64"
COMPATIBLE_MACHINE_pn-zlib-qat = "intel-corei7-64"

XSERVER ?= "${XSERVER_X86_BASE} \
            ${XSERVER_X86_EXT} \
            ${XSERVER_X86_FBDEV} \
            ${XSERVER_X86_I915} \
            ${XSERVER_X86_I965} \
            ${XSERVER_X86_MODESETTING} \
            ${XSERVER_X86_VESA} \
            ${XSERVER_X86_ASPEED_AST} \
           "

SYSLINUX_OPTS = "serial 0 115200"
SERIAL_CONSOLES = "115200;ttyS0 115200;ttyS1 115200;ttyS2"
APPEND += "rootwait console=ttyS0,115200 console=tty0"

IMAGE_FSTYPES += "wic"
WKS_FILE ?= "grub-bootdisk-microcode.wks.in"
WKS_FILE_DEPENDS_append = " intel-microcode"

KMACHINE = "intel-corei7-64"
ALLOW_EMPTY_${KERNEL_PACKAGE_NAME}-devicetree = "1"
MACHINEOVERRIDES =. "intel-corei7-64:"

EFI_PROVIDER = ""
