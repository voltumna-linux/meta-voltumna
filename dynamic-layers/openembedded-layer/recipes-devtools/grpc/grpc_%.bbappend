# doesn't build and not required
DEPENDS:remove:mingw32 = "libnsl2"

EXTRA_OECMAKE:remove:mingw32 = "-DBUILD_SHARED_LIBS=ON"
EXTRA_OECMAKE:append:mingw32 = " -DBUILD_SHARED_LIBS=OFF"
