SUMMARY = "Simple DirectMedia Layer image library v2"
SECTION = "libs"

LICENSE = "Zlib"
LIC_FILES_CHKSUM = "file://LICENSE.txt;md5=fbb0010b2f7cf6e8a13bcac1ef4d2455"

DEPENDS = "tiff zlib libpng jpeg libsdl2 libwebp"

SRC_URI = "http://www.libsdl.org/projects/SDL_image/release/SDL2_image-${PV}.tar.gz"
SRC_URI[sha256sum] = "2213b56fdaff2220d0e38c8e420cbe1a83c87374190cba8c70af2156097ce30a"

S = "${WORKDIR}/SDL2_image-${PV}"

inherit autotools pkgconfig

# Disable the run-time loading of the libs and bring back the soname dependencies.
EXTRA_OECONF += "--disable-jpg-shared --disable-png-shared -disable-tif-shared"

do_configure:prepend() {
    # make autoreconf happy
    touch ${S}/NEWS ${S}/README ${S}/AUTHORS ${S}/ChangeLog
    # Removing these files fixes a libtool version mismatch.
    rm -f ${S}/acinclude/libtool.m4
    rm -f ${S}/acinclude/sdl2.m4
    rm -f ${S}/acinclude/pkg.m4
    rm -f ${S}/acinclude/lt~obsolete.m4
    rm -f ${S}/acinclude/ltoptions.m4
    rm -f ${S}/acinclude/ltsugar.m4
    rm -f ${S}/acinclude/ltversion.m4
}
