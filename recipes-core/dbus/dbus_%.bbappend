FILES:${PN}:append:mingw32 = "\
    ${bindir}/dbus-launch.exe \
    ${bindir}/dbus-run-session.exe \
"

FILES:${PN}-tools:append:mingw32 = "\
    ${bindir}/dbus-send.exe \
    ${bindir}/dbus-monitor.exe \
    ${bindir}/dbus-test-tool.exe \
    ${bindir}/dbus-update-activation-environment.exe \
"

FILES:${PN}-lib:append:mingw32 = "\
    ${bindir}/lib*.dll \
"
