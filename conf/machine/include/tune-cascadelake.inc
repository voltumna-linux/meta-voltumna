# Settings for the GCC(1) cpu-type "cascadelake":
#
#	Intel Cascadelake CPU with 64-bit extensions, MOVBE, MMX, SSE, SSE2, SSE3, SSSE3,
#	SSE4.1, SSE4.2, POPCNT, CX16, SAHF, FXSR, AVX, XSAVE, PCLMUL, FSGSBASE, RDRND,
#	F16C, AVX2, BMI, BMI2, LZCNT, FMA, MOVBE, HLE, RDSEED, ADCX, PREFETCHW, AES,
#	CLFLUSHOPT, XSAVEC, XSAVES, SGX, AVX512F, CLWB, AVX512VL, AVX512BW, AVX512DQ,
#	AVX512CD and AVX512VNNI instruction set support.
#
# This tune is recommended for Intel Cascadelake CPU (and beyond).
#
DEFAULTTUNE ?= "cascadelake-64"

# Include the previous tune to pull in PACKAGE_EXTRA_ARCHS
require tune-skylake.inc

# Extra tune features
TUNEVALID[cascadelake] = "Enable cascadelake specific processor optimizations"
TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'cascadelake', ' -march=cascadelake -mtune=cascadelake ${ADDITIONAL_ISA}', '', d)}"

# Extra tune selections
AVAILTUNES += "cascadelake-64"
TUNE_FEATURES:tune-cascadelake-64 = "${TUNE_FEATURES:tune-x86-64} cascadelake"
BASE_LIB:tune-cascadelake-64 = "lib64"
TUNE_PKGARCH:tune-cascadelake-64 = "cascadelake-64"
PACKAGE_EXTRA_ARCHS:tune-cascadelake-64 = "${PACKAGE_EXTRA_ARCHS:tune-skylake-64} cascadelake-64"
QEMU_EXTRAOPTIONS_cascadelake-64 = " -cpu Cascadelake-Server,check=false"

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
-mno-avx512bitalg \
-mno-avx512vpopcntdq \
"
