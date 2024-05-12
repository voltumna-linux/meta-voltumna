# Settings for the GCC(1) cpu-type "haswell":
#
#     Intel Haswell CPU with 64-bit extensions, MOVBE, MMX, SSE, SSE2, SSE3, SSSE3,
#     SSE4.1, SSE4.2, POPCNT, AVX, AVX2, AES, PCLMUL, FSGSBASE, RDRND, FMA,
#     BMI, BMI2 and F16C instruction set support.
#
# This tune is recommended for Intel Haswell CPU (and beyond).
#
DEFAULTTUNE ?= "haswell-64"

# Include the previous tune to pull in PACKAGE_EXTRA_ARCHS
require conf/machine/include/x86/tune-corei7.inc

# Extra tune features
TUNEVALID[haswell] = "Enable haswell specific processor optimizations"
TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'haswell', ' -march=haswell ${HASWELL_TUNE} -mfpmath=sse', '', d)}"

# Extra tune selections

AVAILTUNES += "haswell-64"
TUNE_FEATURES:tune-haswell-64 = "${TUNE_FEATURES:tune-x86-64} haswell"
BASE_LIB:tune-haswell-64 = "lib64"
TUNE_PKGARCH:tune-haswell-64 = "haswell-64"
PACKAGE_EXTRA_ARCHS:tune-haswell-64 = "${PACKAGE_EXTRA_ARCHS:tune-corei7-64} haswell-64"
QEMU_EXTRAOPTIONS_haswell-64 = " -cpu Haswell"

# If qemu-usermode is enabled, we have to disable avx2 ISA extensions, but we can keep mtune as haswell vs generic
HASWELL_TUNE .= "${@bb.utils.contains('MACHINE_FEATURES', 'qemu-usermode', ' ${QEMU_UNAVAILABLE_ISA}', '-mtune=generic -mavx2', d)}"

QEMU_UNAVAILABLE_ISA = " \
-mno-avx \
-mno-avx2 \
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
"
