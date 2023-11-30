# Settings for the GCC(1) cpu-type "core2":
#
#     Intel Penryn CPU with 64-bit extensions, MMX, SSE, SSE2, SSE3, SSSE3, SSE4.1
#     instruction set support.
#
# This tune is recommended for Penryn CPUs (and beyond).
#
DEFAULTTUNE ?= "penryn-64"

# Include the previous tune to pull in PACKAGE_EXTRA_ARCHS
require conf/machine/include/x86/tune-core2.inc

# Extra tune features
TUNEVALID[penryn] = "Enable penryn specific processor optimizations"
TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'penryn', ' -march=core2 -mtune=core2 -msse4.1 -mfpmath=sse', '', d)}"

# Extra tune selections
AVAILTUNES += "penryn-64"
TUNE_FEATURES:tune-penryn-64 = "${TUNE_FEATURES:tune-x86-64} penryn"
BASE_LIB:tune-penryn-64 = "lib64"
TUNE_PKGARCH:tune-penryn-64 = "penryn-64"
PACKAGE_EXTRA_ARCHS:tune-penryn-64 = "${PACKAGE_EXTRA_ARCHS:tune-core2-64} penryn-64"
QEMU_EXTRAOPTIONS_penryn-64 = " -cpu Penryn"
