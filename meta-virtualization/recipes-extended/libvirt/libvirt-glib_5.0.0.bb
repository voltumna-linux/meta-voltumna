DESCRIPTION = "A toolkit to interact with the virtualization capabilities of recent versions of Linux."
HOMEPAGE = "http://libvirt.org"
LICENSE = "LGPL-2.1-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=4fbd65380cdd255951079008b364516c"

DEPENDS = "glib-2.0 libvirt libxml2 libxslt"

SRC_URI = " \
	git://gitlab.com/libvirt/libvirt-glib;protocol=https;branch=master \
	file://0001-meson.build-allow-crosscompiling-gir-and-doc.patch \
"

SRCREV = "6fe1812162c4679fd7adff4a8b32304aff866797"

inherit meson pkgconfig gobject-introspection gettext vala gtk-doc

GIR_MESON_ENABLE_FLAG = 'enabled'
GIR_MESON_DISABLE_FLAG = 'disabled'
GTKDOC_MESON_ENABLE_FLAG = 'enabled'
GTKDOC_MESON_DISABLE_FLAG = 'disabled'
