SUMMARY = "Implementation of the Tango distributed control system in Rust"
HOMEPAGE = "https://gitlab.com/theorozier/rstango"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3b83ef96387f14655fc854ddc3c6bd57"

inherit rust cargo cargo-update-recipe-crates pkgconfig

SRC_URI = "git://gitlab.com/theorozier/rstango.git;protocol=https;branch=main"
SRCREV = "eb7eb59222c64fb4e317cc89fa3819965dbd9a90"

require ${BPN}-crates.inc

# zeromq-src's build script (cc-rs) compiles the vendored libzmq C++ sources from
# ${UNPACKDIR}/cargo_home. DEBUG_PREFIX_MAP only remaps ${S}/${B}/sysroots, so
# absolute build paths leak into .rodata (__FILE__) and DWARF, tripping the
# buildpaths QA check on tgtop. Extend the prefix map to cover vendored sources.
DEBUG_PREFIX_MAP:append = " -ffile-prefix-map=${UNPACKDIR}/cargo_home=${TARGET_DBGSRC_DIR}/cargo_home"

# Install the workspace libraries (tango, tango_omniorb) next to the tgtop binary
CARGO_INSTALL_LIBRARIES = "1"
