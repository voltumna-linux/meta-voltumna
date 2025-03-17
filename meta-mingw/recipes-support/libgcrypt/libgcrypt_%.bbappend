
# libcap does not support mingw32
PACKAGECONFIG_remove_mingw32 = "capabilities"

FILES_${PN}-dev_append_mingw32 = " \
		${libdir}/*.def \
		${bindir}/hmac256.exe \
		${bindir}/mpicalc.exe \
		"
FILES_dumpsexp-dev_append_mingw32 = " ${bindir}/dumpsexp.exe"

