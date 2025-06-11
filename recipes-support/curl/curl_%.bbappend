PACKAGECONFIG:remove:class-nativesdk:mingw32 = "openssl"
EXTRA_OECONF:append:class-nativesdk:mingw32 = " --without-ssl"
RRECOMMENDS:lib${BPN}:remove:mingw32 = "ca-certificates"

# Configure tests for ioctlsocket FIONBIO fails with GCC-14
# because gcc can now find warnings when compiling the test
# and these warnings are treated as errors
#  conftest.c: In function 'main':
#   conftest.c:137:41: error: passing argument 3 of 'ioctlsocket' from incompatible pointer type [-Wincompatible-pointer-types]
#     137 |         if(0 != ioctlsocket(0, FIONBIO, &flags))
#         |                                         ^~~~~~
#         |                                         |
#         |                                         int *
CFLAGS:append:mingw32 = " -Wno-error=incompatible-pointer-types"
