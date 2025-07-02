EXTRA_OEMAKE:append:mingw32 = " OS=Windows"
FILES:${PN}:append:mingw32 = " ${libdir}/*.dll"
SOLIBS:mingw32 = ".so.*"
SOLIBSDEV:mingw32 = ".so"
