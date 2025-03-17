
# libcap does not support mingw32
PACKAGECONFIG:remove:mingw32 = "capabilities"

FILES:${PN}-dev:append:mingw32 = " \
		${libdir}/*.def \
		${bindir}/hmac256.exe \
		${bindir}/mpicalc.exe \
		"
FILES:dumpsexp-dev:append:mingw32 = " ${bindir}/dumpsexp.exe"

