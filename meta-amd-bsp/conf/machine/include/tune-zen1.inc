DEFAULTTUNE ?= "zen1"

require conf/machine/include/x86/arch-x86.inc

TUNEVALID[zen1] = "Enable AMD x86 (64 bit) Zen 1 Core Architecture specific optimizations"
TUNECONFLICTS[zen1] = "m32 mx32"

TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'zen1', ' -march=znver1', '', d)}"
MACHINEOVERRIDES =. "${@bb.utils.contains('TUNE_FEATURES', 'zen1', 'zen1:', '', d)}"

AVAILTUNES += "zen1"
TUNE_FEATURES:tune-zen1         = "${TUNE_FEATURES:tune-x86-64} zen1"
TUNE_PKGARCH:tune-zen1          = "zen1"
PACKAGE_EXTRA_ARCHS:tune-zen1   = "${PACKAGE_EXTRA_ARCHS:tune-x86-64} zen1"
BASE_LIB:tune-zen1              = "lib64"

# user mode qemu doesn't support zen1
MACHINE_FEATURES_BACKFILL_CONSIDERED:append = " ${@bb.utils.contains('TUNE_FEATURES', 'zen1', 'qemu-usermode', '', d)}"
