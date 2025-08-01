DEFAULTTUNE ?= "zen4"

require conf/machine/include/tune-zen3.inc

TUNEVALID[zen4] = "Enable AMD x86 (64 bit) Zen 3 Core Architecture specific optimizations"
TUNECONFLICTS[zen4] = "m32 mx32"

TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'zen4', ' -march=znver3', '', d)}"
MACHINEOVERRIDES =. "${@bb.utils.contains('TUNE_FEATURES', 'zen4', 'zen4:', '', d)}"

AVAILTUNES += "zen4"
TUNE_FEATURES:tune-zen4         = "${TUNE_FEATURES:tune-x86-64} zen4"
TUNE_PKGARCH:tune-zen4          = "zen4"
PACKAGE_EXTRA_ARCHS:tune-zen4   = "${PACKAGE_EXTRA_ARCHS:tune-zen3} zen4"
BASE_LIB:tune-zen4              = "lib64"

# user mode qemu doesn't support zen4
MACHINE_FEATURES_BACKFILL_CONSIDERED:append = " ${@bb.utils.contains('TUNE_FEATURES', 'zen4', 'qemu-usermode', '', d)}"
