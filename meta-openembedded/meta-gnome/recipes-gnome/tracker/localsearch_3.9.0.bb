SUMMARY = "Tracker miners and metadata extractors"
LICENSE = "GPL-2.0-only & LGPL-2.1-only"
LIC_FILES_CHKSUM = " \
    file://COPYING.GPL;md5=ee31012bf90e7b8c108c69f197f3e3a4 \
    file://COPYING.LGPL;md5=2d5025d4aa3495befef8f17206a5b0a1 \
"

DEPENDS = " \
    intltool-native \
    tinysparql \
    zlib \
"


inherit gnomebase gsettings gobject-introspection vala bash-completion features_check

SRC_URI:append = " \
	file://0001-fix-reproducibility.patch \
	file://0001-Set-header-file-to-a-fixed-path-instead-of-a-host-pa.patch \
"
SRC_URI[archive.sha256sum] = "d42f408dc3fb28fe54f5a9abbf5f1decf5818db9c2e9ec51c09464bdfd0c14b9"

# gobject-introspection is mandatory and cannot be configured
REQUIRED_DISTRO_FEATURES = "gobject-introspection-data"
GIR_MESON_OPTION = ""
VALA_MESON_OPTION = ""

PACKAGECONFIG ??= " \
    ${@bb.utils.contains("LICENSE_FLAGS_ACCEPTED", "commercial", "ffmpeg", "", d)} \
    gexiv2 \
    gstreamer \
    icu \
    libexif \
    libgsf \
    jpeg \
    pdf \
    png \
    tiff \
    raw \
    xml \
    ${@bb.utils.filter('DISTRO_FEATURES', 'seccomp', d)} \
    battery \
"
# Needs tgkill API which musl does not support
# see https://www.openwall.com/lists/musl/2019/08/02/1
PACKAGECONFIG:remove:libc-musl = "seccomp"

PACKAGECONFIG[battery]     = "-Dbattery_detection=upower,-Dbattery_detection=none,upower"
PACKAGECONFIG[cue]     = "-Dcue=enabled,-Dcue=disabled,libcue"
PACKAGECONFIG[ffmpeg]     = "-Dlibav=enabled,-Dlibav=disabled,ffmpeg"
PACKAGECONFIG[gexiv2]     = ",,gexiv2"
PACKAGECONFIG[gstreamer]  = ",,gstreamer1.0 gstreamer1.0-plugins-base"
PACKAGECONFIG[gupnp]      = "-Dgstreamer_backend=gupnp,,gupnp-dlna"
PACKAGECONFIG[gif]        = "-Dgif=enabled,-Dgif=disabled,giflib"
PACKAGECONFIG[icu]        = "-Dcharset_detection=icu,,icu"
PACKAGECONFIG[iso]        = "-Diso=enabled,-Diso=disabled,libosinfo"
PACKAGECONFIG[jpeg]       = "-Djpeg=enabled,-Djpeg=disabled,jpeg"
PACKAGECONFIG[libexif]    = "-Dexif=enabled,-Dexif=disabled,libexif"
PACKAGECONFIG[libgsf]     = "-Dgsf=enabled,-Dgsf=disabled,libgsf"
PACKAGECONFIG[pdf]        = "-Dpdf=enabled,-Dpdf=disabled,poppler"
PACKAGECONFIG[png]        = "-Dpng=enabled,-Dpng=disabled,libpng"
PACKAGECONFIG[tiff]       = "-Dtiff=enabled,-Dtiff=disabled,tiff"
PACKAGECONFIG[raw]       = "-Draw=enabled,-Draw=disabled,libraw"
PACKAGECONFIG[xml]        = "-Dxml=enabled,-Dxml=disabled,libxml2"
PACKAGECONFIG[landlock]        = "-Dlandlock=enabled,-Dlandlock=disabled"

# For security reasons it is strongly recommended to set add meta-security in
# your layers and 'libseccomp + landlock' to PACKAGECONFIG".
PACKAGECONFIG[seccomp] = "-Dseccomp=true,-Dseccomp=false,libseccomp"

EXTRA_OEMESON += " \
    -Dman=false \
    -Dsystemd_user_services=${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)} \
    -Dsystemd_user_services_dir=${systemd_user_unitdir} \
"


FILES:${PN} += " \
    ${datadir} \
    ${libdir}/localsearch-3.0 \
    ${systemd_user_unitdir} \
"
