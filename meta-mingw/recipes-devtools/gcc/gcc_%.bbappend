FILES_${PN}_append_mingw32 = "\
   ${libexecdir}/gcc/${TARGET_SYS}/${BINV}/liblto_plugin-0.dll \
   ${libexecdir}/gcc/${TARGET_SYS}/${BINV}/liblto_plugin.dll.a \
"

INSANE_SKIP_append_mingw32 = " staticdev"
