# Settings for the GCC(1) cpu-type "skylake":
#
#     Intel Skylake CPU with 64-bit extensions, MOVBE, MMX, SSE, SSE2, SSE3, SSSE3,
#     SSE4.1, SSE4.2, POPCNT, AVX, AVX2, AES, PCLMUL, FSGSBASE, RDRND, FMA, BMI,
#     BMI2, F16C, RDSEED, ADCX, PREFETCHW, CLFLUSHOPT, XSAVEC and XSAVES
#     instruction set support.
#
# This tune is recommended for Intel Skylake CPU (and beyond).
#
DEFAULTTUNE ?= "skylake-64"

# Include the previous tune to pull in PACKAGE_EXTRA_ARCHS
require conf/machine/include/tune-corei7.inc

# Extra tune features
TUNEVALID[skylake] = "Enable skylake specific processor optimizations"
TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'skylake', ' -march=skylake ${SKYLAKE_TUNE} -mfpmath=sse', '', d)}"

# Extra tune selections

AVAILTUNES += "skylake-64"
TUNE_FEATURES_tune-skylake-64 = "${TUNE_FEATURES_tune-x86-64} skylake"
BASE_LIB_tune-skylake-64 = "lib64"
TUNE_PKGARCH_tune-skylake-64 = "skylake-64"
PACKAGE_EXTRA_ARCHS_tune-skylake-64 = "${PACKAGE_EXTRA_ARCHS_tune-core2-64} skylake-64"
QEMU_EXTRAOPTIONS_skylake-64 = " -cpu Skylake-Client"

# If qemu-usermode is enabled, we have to disable avx2 ISA extensions, but we can keep mtune as skylake vs generic
SKYLAKE_TUNE .= "${@bb.utils.contains('MACHINE_FEATURES', 'qemu-usermode', ' -mtune=skylake ${QEMU_UNAVAILABLE_ISA}', '-mtune=generic -mavx2', d)}"

QEMU_UNAVAILABLE_ISA = " \
-mno-avx \
-mno-avx2 \
-mno-avx512f \
-mno-avx512cd \
-mno-avx512dq \
-mno-avx512bw \
-mno-avx512vl \
-mno-avx512ifma \
-mno-avx512vbmi \
-mno-avx512vbmi2 \
-mno-avx512vnni \
-mno-avx512bitalg \
"

OPENBLAS_TARGET = "HASWELL"
