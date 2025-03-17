DEFAULTTUNE ?= "zen3"

require conf/machine/include/tune-zen2.inc

TUNEVALID[zen3] = "Enable AMD x86 (64 bit) Zen 3 Core Architecture specific optimizations"
TUNECONFLICTS[zen3] = "m32 mx32"

TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'zen3', ' -march=znver3', '', d)}"
MACHINEOVERRIDES =. "${@bb.utils.contains('TUNE_FEATURES', 'zen3', 'zen3:', '', d)}"

AVAILTUNES += "zen3"
TUNE_FEATURES:tune-zen3         = "${TUNE_FEATURES:tune-x86-64} zen3"
TUNE_PKGARCH:tune-zen3          = "zen3"
PACKAGE_EXTRA_ARCHS:tune-zen3   = "${PACKAGE_EXTRA_ARCHS:tune-zen2} zen3"
BASE_LIB:tune-zen3              = "lib64"

# user mode qemu doesn't support zen3
MACHINE_FEATURES_BACKFILL_CONSIDERED:append = " ${@bb.utils.contains('TUNE_FEATURES', 'zen3', 'qemu-usermode', '', d)}"

