DEFAULTTUNE ?= "zen2"

require conf/machine/include/tune-zen1.inc

TUNEVALID[zen2] = "Enable AMD x86 (64 bit) Zen 2 Core Architecture specific optimizations"
TUNECONFLICTS[zen2] = "m32 mx32"

TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'zen2', ' -march=znver2', '', d)}"
MACHINEOVERRIDES =. "${@bb.utils.contains('TUNE_FEATURES', 'zen2', 'zen2:', '', d)}"

AVAILTUNES += "zen2"
TUNE_FEATURES:tune-zen2         = "${TUNE_FEATURES:tune-x86-64} zen2"
TUNE_PKGARCH:tune-zen2          = "zen2"
PACKAGE_EXTRA_ARCHS:tune-zen2   = "${PACKAGE_EXTRA_ARCHS:tune-zen1} zen2"
BASE_LIB:tune-zen2              = "lib64"

# user mode qemu doesn't support zen2
MACHINE_FEATURES_BACKFILL_CONSIDERED:append = " ${@bb.utils.contains('TUNE_FEATURES', 'zen2', 'qemu-usermode', '', d)}"

