EXTRA_OECONF:append:sdkmingw32 = " --disable-nls"
LDFLAGS:append:sdkmingw32 = " -Wl,-static"

DEPENDS:remove:sdkmingw32 = "nativesdk-gettext"
DEPENDS:remove:sdkmingw32 = "nativesdk-flex"

FILES:${PN}-staticdev:append:sdkmingw32 = " ${libdir}/bfd-plugins/lib*.a"
