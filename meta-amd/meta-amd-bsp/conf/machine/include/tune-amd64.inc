DEFAULTTUNE ?= "amd64"

require conf/machine/include/x86/arch-x86.inc
require conf/machine/include/x86/x86-base.inc

# AMD x86 64-bit
TUNEVALID[amd64] = "Enable AMD x86 (64 bit) specific processor optimizations"
TUNECONFLICTS[amd64] = "m32 mx32"

# Extra tune selections
AVAILTUNES += "amd64"
TUNE_FEATURES:tune-amd64 = "m64"
BASE_LIB:tune-amd64 = "lib64"
TUNE_PKGARCH:tune-amd64 = "amd64"
PACKAGE_EXTRA_ARCHS:tune-amd64 = "${TUNE_PKGARCH:tune-amd64}"
