FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

DEPENDS:append:class-nativesdk:mingw32 = " nativesdk-mingw-libgnurx"
