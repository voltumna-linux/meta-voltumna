FILES_libstdc++_append_mingw32 = " ${bindir}/libstdc++*.dll"
FILES_libstdc++-staticdev_append_mingw32 = " ${libdir}/libstdc++.dll.a*"
FILES_libssp_append_mingw32 = " ${bindir}/libssp*.dll"
# FILES_libgomp_append_mingw32 = " ${bindir}/libgomp*.dll"

RUNTIMETARGET_remove_mingw32 = "libatomic libgomp"
RUNTIMETARGET_remove_mingw32 = "libitm"

# Intel Memory Protection Extension library for x86 builds are now enabled
# by default. However, it does not build for mingw32, so remove it from
# mingw builds
RUNTIMETARGET_remove_mingw32 = "libmpx"

DEPENDS_append_mingw32 = " nativesdk-mingw-w64-winpthreads"
