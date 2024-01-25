# Settings for the GCC(1) cpu-type "tremont":
#
#     Intel Tremont CPU with 64-bit extensions, MOVBE, MMX, SSE, SSE2, SSE3, SSSE3, SSE4.1,
#     SSE4.2, POPCNT, AES, PREFETCHW, PCLMUL, RDRND, XSAVE, XSAVEC, XSAVES, XSAVEOPT, FSGSBASE,
#     PTWRITE, RDPID, SGX, UMIP, GFNI-SSE, CLWB, MOVDIRI, MOVDIR64B, CLDEMOTE and 
#     WAITPKG instruction set support.
#
# This tune is recommended for Tremont CPUs (and beyond).
#
DEFAULTTUNE ?= "tremont-64"

# Include the previous tune to pull in PACKAGE_EXTRA_ARCHS
require conf/machine/include/x86/tune-core2.inc

# Extra tune features
TUNEVALID[tremont] = "Enable tremont specific processor optimizations"
TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'tremont', ' -march=tremont -mtune=tremont -mfpmath=sse -msse4.2', '', d)}"

# Extra tune selections
AVAILTUNES += "tremont-64"
TUNE_FEATURES:tune-tremont-64 = "${TUNE_FEATURES:tune-x86-64} tremont"
BASE_LIB:tune-tremont-64 = "lib64"
TUNE_PKGARCH:tune-tremont-64 = "tremont-64"
PACKAGE_EXTRA_ARCHS:tune-tremont-64 = "${PACKAGE_EXTRA_ARCHS:tune-core2-64} tremont-64"
QEMU_EXTRAOPTIONS_tremont-64 = " -cpu Nehalem"
