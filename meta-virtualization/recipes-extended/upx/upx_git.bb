SUMMARY = "Ultimate executable compressor."
HOMEPAGE = "https://upx.github.io/"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=353753597aa110e0ded3508408c6374a"

# Note: DO NOT use released tarball in favor of the git repository with submodules.
# it makes maintenance easier for CVEs or other issues.

SRCREV_upx = "ca97430db28bf264f4007118555c10f63be2a9c8"
PV = "5.0.1+git${SRCPV}"

# SRCREVs are from:
#   git submodule status | awk '{ commit_hash = $1; sub(/vendor\//, "", $2); gsub("-", "_", $2); printf "SRCREV_vendor_%s = \"%s\"\n", $2, commit_hash }'
#
# with two substitions for invalid SRCREVs (hence why the gitsm fetcher
# has issues)
SRCREV_vendor_doctest = "835aaee34666173532e98437b057f37b385076c9"
SRCREV_vendor_lzma_sdk = "f9637f9f563d17b6ecf33ae2212dcd44866bfb25"
SRCREV_vendor_ucl = "a60611d342b0b7d2924c495ebaa1910e4c3c3fe6"
SRCREV_vendor_valgrind = "b054e44ea1b6d630853ed74d33e0934ef4642efc"
SRCREV_vendor_zlib = "0a41a7d0a974d0b43afe4afe4b8025c8f144474e"

# This is broken for commits newer than 4.2.4 with invalid SRCREVs being reported
# by the git submodules. We switch back to individual fetches while this is
# investigated.
# SRC_URI = "gitsm://github.com/upx/upx;protocol=https;;name=upx;branch=devel"
SRCREV_FORMAT = "upx"
SRC_URI = "git://github.com/upx/upx;name=upx;branch=devel;protocol=https \
           git://github.com/upx/upx-vendor-doctest;name=vendor_doctest;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/vendor/doctest;branch=upx-vendor;protocol=https \
           git://github.com/upx/upx-vendor-lzma-sdk;name=vendor_lzma_sdk;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/vendor/lzma-sdk;branch=upx-vendor;protocol=https \
           git://github.com/upx/upx-vendor-ucl;name=vendor_ucl;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/vendor/ucl;branch=upx-vendor;protocol=https \
           git://github.com/upx/upx-vendor-zlib;name=vendor_zlib;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/vendor/zlib;branch=upx-vendor;protocol=https \
           git://github.com/upx/upx-vendor-valgrind;name=vendor_valgrind;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/vendor/valgrind;branch=upx-vendor;protocol=https \
	   "

inherit pkgconfig cmake

BBCLASSEXTEND = "native"
