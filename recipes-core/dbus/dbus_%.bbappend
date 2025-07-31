# There seems to be a mingw build issue where if either of these are specified,
# the mingw build fails in do_compile. Work around it for now.
EXTRA_OEMESON:remove:mingw32 = "-Dtraditional_activation=true -Dtraditional_activation=false"

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
