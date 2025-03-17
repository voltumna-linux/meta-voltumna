EXTRA_OECONF:append:mingw32 = " --enable-static"

FILESEXTRAPATHS:prepend:mingw32 := "${THISDIR}/${BPN}:"
SRC_URI:append:mingw32 = " \
		"

FILES:libgettextlib:mingw32 = "${bindir}/libgettextlib-*.dll"
FILES:libgettextsrc:mingw32 = "${bindir}/libgettextsrc-*.dll"

PACKAGES:prepend:mingw32 = "libintl "
FILES:libintl:mingw32 = "${bindir}/libintl*.dll"

