SUMMARY = "Implementation of the Tango distributed control system in Rust"
HOMEPAGE = "https://gitlab.com/theorozier/rstango"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3b83ef96387f14655fc854ddc3c6bd57"

inherit rust cargo cargo-update-recipe-crates pkgconfig

SRC_URI = "git://gitlab.com/theorozier/rstango.git;protocol=https;branch=main"
SRCREV = "c21cf0ef43ac637f44375d6e6e05e37938f3bf1a"
# S = "${UNPACKDIR}/git"

DEPENDS += "omniorb"

require ${BPN}-crates.inc

# Install the workspace libraries (tango, tango_omniorb) next to the tgtop binary
CARGO_INSTALL_LIBRARIES = "1"
