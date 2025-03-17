
# glib always provides bash-completion output, package the output but prevent
# the dependency chain on bash (via bash-completion) for mingw32 targets only.
RDEPENDS:${PN}-bash-completion:remove:mingw32 = "bash-completion"

# libmount is not buildable for mingw/windows
PACKAGECONFIG:remove:mingw32 = "libmount"

FILES:${PN}:append:mingw32 = " \
		${bindir}/lib*.dll \
		${libexecdir}/*gio-querymodules.exe \
		"
FILES:${PN}-dev:append:mingw32 = " ${libdir}/*.def"
FILES:${PN}-utils:append:mingw32 = " ${bindir}/*.exe"

