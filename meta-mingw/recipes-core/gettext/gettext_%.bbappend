EXTRA_OECONF_append_mingw32 = " --enable-static"

FILESEXTRAPATHS_prepend_mingw32 := "${THISDIR}/${BPN}:"
SRC_URI_append_mingw32 = " \
		"

FILES_libgettextlib_mingw32 = "${bindir}/libgettextlib-*.dll"
FILES_libgettextsrc_mingw32 = "${bindir}/libgettextsrc-*.dll"

PACKAGES_prepend_mingw32 = "libintl "
FILES_libintl_mingw32 = "${bindir}/libintl*.dll"

