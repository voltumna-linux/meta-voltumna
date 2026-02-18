SUMMARY = "Building blocks for modern GNOME applications"
LICENSE="LGPL-2.1-or-later"
LIC_FILES_CHKSUM = "file://COPYING;md5=4fbd65380cdd255951079008b364516c"

GNOMEBASEBUILDCLASS = "meson"

DEPENDS = " \
    sassc-native \
    gtk4 \
"

inherit gnomebase gobject-introspection gtk-doc vala features_check

SRC_URI[archive.sha256sum] = "f54481638e921b1e42a7edd16c4fadd5eb859f8ef1425285618821c844b38d92"

ANY_OF_DISTRO_FEATURES = "${GTK3DISTROFEATURES}"
REQUIRED_DISTRO_FEATURES = "opengl"

GIR_MESON_ENABLE_FLAG = 'enabled'
GIR_MESON_DISABLE_FLAG = 'disabled'
GTKDOC_MESON_OPTION = 'gtk_doc'

PACKAGECONFIG[examples] = "-Dexamples=true,-Dexamples=false"

FILES:${PN} += "${datadir}/metainfo"
