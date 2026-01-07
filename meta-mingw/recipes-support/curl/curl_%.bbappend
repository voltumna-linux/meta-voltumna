PACKAGECONFIG:remove:class-nativesdk:mingw32 = "openssl"
PACKAGECONFIG:append:class-nativesdk:mingw32 = " schannel"
RRECOMMENDS:lib${BPN}:remove:mingw32 = "ca-certificates"
