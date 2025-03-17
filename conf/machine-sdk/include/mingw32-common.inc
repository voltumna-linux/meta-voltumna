SDK_OS = "mingw32"
SDK_VENDOR:mingw32 = "-w64"
SDK_VENDOR:sdkmingw32 = "-w64"

NATIVESDKLIBC = "libc-mingw"

PREFERRED_PROVIDER_virtual/nativesdk-${SDK_PREFIX}libc-for-gcc_mingw32 = "nativesdk-mingw-w64-runtime"
PREFERRED_PROVIDER_virtual/nativesdk-${SDK_PREFIX}libc-initial_mingw32 = "nativesdk-mingw-w64-runtime"
PREFERRED_PROVIDER_virtual/nativesdk-libc = "nativesdk-mingw-w64-runtime"
PREFERRED_PROVIDER_virtual/nativesdk-libintl = "nativesdk-gettext"
PREFERRED_PROVIDER_virtual/nativesdk-libiconv = "nativesdk-libiconv"

USE_NLS:mingw32 = "no"

FILES:${PN}-staticdev:append:mingw32 = " ${libdir}/*.lib"
ALLOW_EMPTY:${PN}:mingw32 = "1"

DISTRO_FEATURES_FILTER_NATIVESDK:remove:mingw32 = "debuginfod"

# Do what amounts to a NOOP
SDK_PACKAGING_FUNC = "do_compile"

# Causes an endless loop
#SDKTAROPTS_append = " -h --hard-dereference"

SDKUSE_NLS = "no"
SDKIMAGE_LINGUAS = ""
SDK_DEPENDS:remove = "nativesdk-glibc-locale"
SDK_DEPENDS:remove = "nativesdk-glibc-utils"

SDKPKGSUFFIX = "nativesdk-mingw32"

MACHINEOVERRIDES .= ":sdkmingw32"

TESTSDK_CLASS_NAME = "oeqa.sdkmingw.testsdk.TestSDKMinGW"
TESTSDKEXT_CLASS_NAME = ""

WINDRES:mingw32 = "${HOST_PREFIX}windres --include-dir=${STAGING_INCDIR}"
RC:mingw32 = "${WINDRES}"

export WINDRES
export RC

BB_BASEHASH_IGNORE_VARS:append = " WINDRES RC"

# Needed to override no-static-libs.inc
DISABLE_STATIC:mingw32 = ""

# disable security flags
GCCPIE:mingw32 = ""

# wine and wineserver are required to test MinGW SDKs
HOSTTOOLS += "${@'wine wineserver' if (bb.utils.contains_any('IMAGE_CLASSES', 'testsdk', True, False, d) or any(x in (d.getVar("BBINCLUDED") or "") for x in ["testsdk.bbclass"])) else ''}"

