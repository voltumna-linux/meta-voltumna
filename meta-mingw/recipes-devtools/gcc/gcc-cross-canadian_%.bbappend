INSANE_SKIP:${PN}:append:sdkmingw32 = " staticdev"
EXTRA_OECONF:append:sdkmingw32 = " --disable-nls"
LDFLAGS:append:sdkmingw32 = " -Wl,-static"
EXEEXT:sdkmingw32 = ".exe"
ELFUTILS:sdkmingw32 = ""
DEPENDS:remove:sdkmingw32 = "nativesdk-gettext"

# With plugins enabled, it will output 'dll.a' files that are mistaken
# for ELF which can trigger a failure.  Simply avoid processing these
# to avoid the error condition.
INHIBIT_PACKAGE_DEBUG_SPLIT = '1'
