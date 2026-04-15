DEFAULTTUNE ?= "ppc7450"

require conf/machine/include/powerpc/arch-powerpc.inc

TUNEVALID[ppc7450] = "Enable ppc7450 specific processor optimizations"
TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'ppc7450', ' -mcpu=7450 -mno-spe', '', d)}"

AVAILTUNES += "ppc7450"
TUNE_FEATURES_tune-ppc7450 = "m32 fpu-hard ppc7450 altivec bigendian"
TUNE_PKGARCH_tune-ppc7450 = "ppc7450"
PACKAGE_EXTRA_ARCHS_tune-ppc7450 = "${PACKAGE_EXTRA_ARCHS_tune-powerpc} ppc7450"

# glibc configure options to get 7450 specific library (for sqrt)
#GLIBC_EXTRA_OECONF += "${@bb.utils.contains('TUNE_FEATURES', 'ppc7450', '--with-cpu=power4', '', d)}"

QEMU_EXTRAOPTIONS_ppc7450 = " -cpu 7450"
