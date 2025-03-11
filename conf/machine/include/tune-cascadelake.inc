# Settings for the GCC(1) cpu-type "cascadelake":
#
#     Intel Cascadelake CPU with 64-bit extensions, MOVBE, MMX, SSE, SSE2, SSE3, SSSE3,
#     SSE4.1, SSE4.2, POPCNT, PKU, AVX, AVX2, AES, PCLMUL, FSGSBASE, RDRND, FMA, BMI,
#     BMI2, F16C, RDSEED, ADCX, PREFETCHW, CLFLUSHOPT, XSAVEC, XSAVES, AVX512F, CLWB,
#     AVX512VL, AVX512BW, AVX512DQ, AVX512CD and AVX512VNNI instruction set support.
#
# This tune is recommended for Intel Cascadelake CPU (and beyond).
#
DEFAULTTUNE ?= "cascadelake-64"

# Include the previous tune to pull in PACKAGE_EXTRA_ARCHS
require conf/machine/include/tune-corei7.inc

# Extra tune features
TUNEVALID[cascadelake] = "Enable cascadelake specific processor optimizations"
TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'cascadelake', ' -march=cascadelake ${CASCADELAKE_TUNE} -mfpmath=sse', '', d)}"

# Extra tune selections

AVAILTUNES += "cascadelake-64"
TUNE_FEATURES_tune-cascadelake-64 = "${TUNE_FEATURES_tune-x86-64} cascadelake"
BASE_LIB_tune-cascadelake-64 = "lib64"
TUNE_PKGARCH_tune-cascadelake-64 = "cascadelake-64"
PACKAGE_EXTRA_ARCHS_tune-cascadelake-64 = "${PACKAGE_EXTRA_ARCHS_tune-core2-64} cascadelake-64"
QEMU_EXTRAOPTIONS_cascadelake-64 = " -cpu Cascadelake-Server"

CASCADELAKE_TUNE .= "${@bb.utils.contains('MACHINE_FEATURES', 'qemu-usermode', ' ${QEMU_UNAVAILABLE_ISA}', '-mavx2', d)}"

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

OPENBLAS_TARGET = "SKYLAKEX"
