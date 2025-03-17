# The assembly file that encodes the DTD string into wayland-scanner is not
# compatible with i686 MinGW
PACKAGECONFIG_remove_mingw32_i686 = "dtd-validation"

EXTRA_OECONF_class-nativesdk_mingw32 = "--disable-documentation --disable-libraries"
EXTRA_OEMESON_class-nativesdk_mingw32 = "-Ddocumentation=false -Dlibraries=false"

