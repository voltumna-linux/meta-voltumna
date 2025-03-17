PACKAGECONFIG:remove:class-nativesdk:mingw32 = "openssl"
EXTRA_OECONF:append:class-nativesdk:mingw32 = " --without-ssl"
RRECOMMENDS:lib${BPN}:remove:mingw32 = "ca-certificates"
