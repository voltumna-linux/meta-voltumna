EXTRA_OECONF_append_sdkmingw32 = " --disable-nls"
LDFLAGS_append_sdkmingw32 = " -Wl,-static"

DEPENDS_remove_sdkmingw32 = "nativesdk-gettext"
DEPENDS_remove_sdkmingw32 = "nativesdk-flex"
