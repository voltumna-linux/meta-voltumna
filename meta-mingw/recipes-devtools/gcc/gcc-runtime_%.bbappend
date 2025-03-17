FILES:libstdc++:append:mingw32 = " ${bindir}/libstdc++*.dll"
FILES:libstdc++-staticdev:append:mingw32 = " ${libdir}/libstdc++.dll.a*"
FILES:libssp:append:mingw32 = " ${bindir}/libssp*.dll"
# FILES:libgomp:append:mingw32 = " ${bindir}/libgomp*.dll"

RUNTIMETARGET:remove:mingw32 = "libatomic libgomp"
RUNTIMETARGET:remove:mingw32 = "libitm"

# Intel Memory Protection Extension library for x86 builds are now enabled
# by default. However, it does not build for mingw32, so remove it from
# mingw builds
RUNTIMETARGET:remove:mingw32 = "libmpx"

DEPENDS:append:mingw32 = " nativesdk-mingw-w64-winpthreads"
