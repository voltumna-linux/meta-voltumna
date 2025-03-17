DEPENDS:append:mingw32 = " nativesdk-mingw-w64-winpthreads"

FILES:${PN}:append:mingw32 = " ${bindir}/libgcc*.dll"
FILES:${PN}-dev:append:mingw32 = " ${base_libdir}/libgcc*.a"

do_install:append:mingw32 () {
	# move the .dll files into bindir
	install -d ${D}${bindir}
	mv ${D}${base_libdir}/libgcc*.dll ${D}${bindir}/
}
