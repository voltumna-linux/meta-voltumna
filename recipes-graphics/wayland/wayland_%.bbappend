# The assembly file that encodes the DTD string into wayland-scanner is not
# compatible with i686 MinGW
PACKAGECONFIG:remove:mingw32:i686 = "dtd-validation"

EXTRA_OEMESON:class-nativesdk:mingw32 = "-Ddocumentation=false -Dlibraries=false -Dtests=false"

