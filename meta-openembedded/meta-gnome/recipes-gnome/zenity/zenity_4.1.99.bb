SUMMARY = "Display dialog boxes from the command line and shell scripts"
SECTION = "x11/gnome"
LICENSE = "LGPL-2.1-or-later"
LIC_FILES_CHKSUM = "file://COPYING;md5=4fbd65380cdd255951079008b364516c"

inherit gnomebase pkgconfig itstool gtk-icon-cache features_check gettext

DEPENDS = " \
    desktop-file-utils-native \
    help2man-native \
    hicolor-icon-theme \
    gtk4 \
    gtk4-native \
    libadwaita \
"

ANY_OF_DISTRO_FEATURES = "${GTK3DISTROFEATURES}"
REQUIRED_DISTRO_FEATURES = "opengl"
GTKIC_VERSION = "4"

SRC_URI[archive.sha256sum] = "6fe2aa313c71e91ffa55b11dbec7904f31a40303e0a3f6016820ff6dee329ee2"

PACKAGECONFIG ?= "webkitgtk"
PACKAGECONFIG[webkitgtk] = "-Dwebkitgtk=true,-Dwebkitgtk=false,webkitgtk"

FILES:${PN}-doc = "${datadir}/man ${datadir}/help"
