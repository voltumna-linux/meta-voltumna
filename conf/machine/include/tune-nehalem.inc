# Settings for the GCC(1) cpu-type "nehalem":
#
#     Intel Nehalem CPU with 64-bit extensions, MMX, SSE, SSE2, SSE3, SSSE3, SSE4.1,
#     SSE4.2 and POPCNT instruction set support.
#
# This tune is recommended for Intel Nehalem and Silvermont (e.g. Bay Trail) CPUs
# (and beyond).
#
DEFAULTTUNE ?= "nehalem-64"

# Include the previous tune to pull in PACKAGE_EXTRA_ARCHS
require conf/machine/include/tune-core2.inc

# Extra tune features
TUNEVALID[nehalem] = "Enable nehalem specific processor optimizations"
TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'nehalem', ' -march=nehalem -mfpmath=sse -msse4.2', '', d)}"

# Extra tune selections
AVAILTUNES += "nehalem-32"
TUNE_FEATURES_tune-nehalem-32 = "${TUNE_FEATURES_tune-x86} nehalem"
BASE_LIB_tune-nehalem-32 = "lib"
TUNE_PKGARCH_tune-nehalem-32 = "nehalem-32"
PACKAGE_EXTRA_ARCHS_tune-nehalem-32 = "${PACKAGE_EXTRA_ARCHS_tune-core2-32} nehalem-32"
QEMU_EXTRAOPTIONS_nehalem-32 = " -cpu Nehalem,check=false"

AVAILTUNES += "nehalem-64"
TUNE_FEATURES_tune-nehalem-64 = "${TUNE_FEATURES_tune-x86-64} nehalem"
BASE_LIB_tune-nehalem-64 = "lib64"
TUNE_PKGARCH_tune-nehalem-64 = "nehalem-64"
PACKAGE_EXTRA_ARCHS_tune-nehalem-64 = "${PACKAGE_EXTRA_ARCHS_tune-core2-64} nehalem-64"
QEMU_EXTRAOPTIONS_nehalem-64 = " -cpu Nehalem,check=false"

AVAILTUNES += "nehalem-64-x32"
TUNE_FEATURES_tune-nehalem-64-x32 = "${TUNE_FEATURES_tune-x86-64-x32} nehalem"
BASE_LIB_tune-nehalem-64-x32 = "libx32"
TUNE_PKGARCH_tune-nehalem-64-x32 = "nehalem-64-x32"
PACKAGE_EXTRA_ARCHS_tune-nehalem-64-x32 = "${PACKAGE_EXTRA_ARCHS_tune-core2-64-x32} nehalem-64-x32"
QEMU_EXTRAOPTIONS_nehalem-64-x32 = " -cpu Nehalem,check=false"

OPENBLAS_TARGET = "NEHALEM"
