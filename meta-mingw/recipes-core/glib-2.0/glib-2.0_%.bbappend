
# glib always provides bash-completion output, package the output but prevent
# the dependency chain on bash (via bash-completion) for mingw32 targets only.
RDEPENDS_${PN}-bash-completion_remove_mingw32 = "bash-completion"

# libmount is not buildable for mingw/windows
PACKAGECONFIG_remove_mingw32 = "libmount"

FILES_${PN}_append_mingw32 = " \
		${bindir}/lib*.dll \
		${libexecdir}/*gio-querymodules.exe \
		"
FILES_${PN}-dev_append_mingw32 = " ${libdir}/*.def"
FILES_${PN}-utils_append_mingw32 = " ${bindir}/*.exe"

