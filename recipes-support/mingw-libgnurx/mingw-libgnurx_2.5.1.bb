# Copyright (C) 2021 Khem Raj <raj.khem@gmail.com>
# Released under the MIT license (see COPYING.MIT for the terms)
LICENSE = "LGPL-2.1-only"
LIC_FILES_CHKSUM = "file://COPYING.LIB;md5=bbb461211a33b134d42ed5ee802b37ff"

SRC_URI = "http://download.sourceforge.net/mingw/Other/UserContributed/regex/mingw-regex-${PV}/mingw-libgnurx-${PV}-src.tar.gz \
           file://0001-Honor-DESTDIR-variable-during-install.patch \
           file://0002-Add-autotool-files.patch \
           "
SRC_URI[sha256sum] = "7147b7f806ec3d007843b38e19f42a5b7c65894a57ffc297a76b0dcd5f675d76"

UPSTREAM_CHECK_URI = "https://sourceforge.net/projects/mingw/files/Other/UserContributed/regex/"
UPSTREAM_CHECK_REGEX = "mingw-regex-(?P<pver>\d+(\.\d+)+)"

inherit autotools

# Specify any options you want to pass to the configure script using EXTRA_OECONF:
EXTRA_OECONF = ""

BBCLASSEXTEND = "nativesdk"
