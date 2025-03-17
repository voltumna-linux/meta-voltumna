FILES:${PN}:append:mingw32 = "\
   ${libexecdir}/gcc/${TARGET_SYS}/${BINV}/liblto_plugin-0.dll \
   ${libexecdir}/gcc/${TARGET_SYS}/${BINV}/liblto_plugin.dll.a \
"

INSANE_SKIP:append:mingw32 = " staticdev"
