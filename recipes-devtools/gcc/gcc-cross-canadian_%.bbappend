INSANE_SKIP_${PN}_append_sdkmingw32 = " staticdev"
EXTRA_OECONF_append_sdkmingw32 = " --disable-nls"
LDFLAGS_append_sdkmingw32 = " -Wl,-static"
EXEEXT_sdkmingw32 = ".exe"
ELFUTILS_sdkmingw32 = ""
DEPENDS_remove_sdkmingw32 = "nativesdk-gettext"

# With plugins enabled, it will output 'dll.a' files that are mistaken
# for ELF which can trigger a failure.  Simply avoid processing these
# to avoid the error condition.
INHIBIT_PACKAGE_DEBUG_SPLIT = '1'
