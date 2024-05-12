# Settings for the GCC(1) cpu-type "skylake":
#
#     Intel Skylake CPU with 64-bit extensions, MOVBE, MMX, SSE, SSE2, SSE3, SSSE3,
#     SSE4.1, SSE4.2, POPCNT, CX16, SAHF, FXSR, AVX, XSAVE, PCLMUL, FSGSBASE, RDRND,
#     F16C, AVX2, BMI, BMI2, LZCNT, FMA, MOVBE, HLE, RDSEED, ADCX, PREFETCHW, AES,
#     CLFLUSHOPT, XSAVEC, XSAVES and SGX instruction set support.
#
# This tune is recommended for Intel Skylake CPU (and beyond).
#
DEFAULTTUNE ?= "skylake-64"

# Include the previous tune to pull in PACKAGE_EXTRA_ARCHS
require conf/machine/include/x86/tune-corei7.inc

# Extra tune features
TUNEVALID[skylake] = "Enable skylake specific processor optimizations"
TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'skylake', ' -march=skylake -mtune=skylake ${ADDITIONAL_ISA}', '', d)}"

# Extra tune selections
AVAILTUNES += "skylake-64"
TUNE_FEATURES:tune-skylake-64 = "${TUNE_FEATURES:tune-x86-64} skylake"
BASE_LIB:tune-skylake-64 = "lib64"
TUNE_PKGARCH:tune-skylake-64 = "skylake-64"
PACKAGE_EXTRA_ARCHS:tune-skylake-64 = "${PACKAGE_EXTRA_ARCHS:tune-corei7-64} skylake-64"
QEMU_EXTRAOPTIONS_skylake-64 = " -cpu Skylake-Client,check=false"

OPENBLAS_TARGET = "SKYLAKEX"

ADDITIONAL_ISA = "${@bb.utils.contains('MACHINE_FEATURES', 'highly-optimized', '', ' ${ADVANCED_ISA}', d)}"
ADVANCED_ISA = " \
-mno-avx512f \
-mno-avx512er \
-mno-avx512cd \
-mno-avx512pf \
-mno-avx512dq \
-mno-avx512bw \
-mno-avx512vl \
-mno-avx512ifma \
-mno-avx512vbmi \
-mno-avx512vbmi2 \
-mno-avx512vnni \
-mno-avx5124vnniw \
-mno-avx512bitalg \
-mno-avx512vpopcntdq \
-mno-avx5124fmaps \
"

