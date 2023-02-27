# Settings for the GCC(1) cpu-type "broadwell":
#
#     Intel Broadwell CPU with 64-bit extensions, MOVBE, MMX, SSE, SSE2, SSE3, SSSE3, 
#     SSE4.1, SSE4.2, POPCNT, AVX, AVX2, AES, PCLMUL, FSGSBASE, RDRND, FMA, 
#     BMI, BMI2, F16C, RDSEED ADCX and PREFETCHW instruction set support.
#
# This tune is recommended for Intel Broadwell CPU (and beyond).
#
DEFAULTTUNE ?= "broadwell-64"

# Include the previous tune to pull in PACKAGE_EXTRA_ARCHS
require conf/machine/include/x86/tune-corei7.inc

# Extra tune features
TUNEVALID[broadwell] = "Enable broadwell specific processor optimizations"
TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'broadwell', ' -march=broadwell ${BROADWELL_TUNE} -mfpmath=sse', '', d)}"

# Extra tune selections

AVAILTUNES += "broadwell-64"
TUNE_FEATURES:tune-broadwell-64 = "${TUNE_FEATURES:tune-x86-64} broadwell"
BASE_LIB:tune-broadwell-64 = "lib64"
TUNE_PKGARCH:tune-broadwell-64 = "broadwell-64"
PACKAGE_EXTRA_ARCHS:tune-broadwell-64 = "${PACKAGE_EXTRA_ARCHS:tune-corei7-64} broadwell-64"
QEMU_EXTRAOPTIONS_broadwell-64 = " -cpu broadwell"


# Disable QEMU usermode by default (get avx2)
MACHINE_FEATURES:remove = "qemu-usermode"

# If qemu-usermode is enabled, we have to disable avx2 ISA extensions, but we can keep mtune as broadwell vs generic
BROADWELL_TUNE .= "${@bb.utils.contains('MACHINE_FEATURES', 'qemu-usermode', ' -mtune=broadwell', '-mtune=generic -mavx2', d)}"
