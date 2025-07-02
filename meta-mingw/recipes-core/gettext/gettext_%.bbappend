EXTRA_OECONF:append:mingw32 = " --enable-static"

# GCC-14 treats this warning as error which results in
# build failures on gnulib imported code which is dated in
# gettext
# ../../../gettext-0.22.5/gettext-tools/gnulib-lib/localtime.c: In function 'rpl_localtime':
#../../../gettext-0.22.5/gettext-tools/gnulib-lib/localtime.c:66:24: error: initialization of 'char *' from incompatible pointer type 'char **' [-Wincompatible-pointer-types]
#   66 |         for (char *s = env; *s != NULL; s++)
#      |                        ^~~
CFLAGS:append:mingw32 = " -Wno-error=incompatible-pointer-types"

FILESEXTRAPATHS:prepend:mingw32 := "${THISDIR}/${BPN}:"
SRC_URI:append:mingw32 = " \
		"

FILES:libgettextlib:mingw32 = "${bindir}/libgettextlib-*.dll"
FILES:libgettextsrc:mingw32 = "${bindir}/libgettextsrc-*.dll"

PACKAGES:prepend:mingw32 = "libintl ${LOCALEBASEPN}-locale-alias "
FILES:libintl:mingw32 = "${bindir}/libintl*.dll"
FILES:${LOCALEBASEPN}-locale-alias = "${datadir}/locale/locale.alias"

