SUMMARY = "Generator for quadlet files"
DESCRIPTION = "Podlet generates Podman Quadlet files from a Podman command, compose file, or existing object."
LICENSE = "MPL-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=f75d2927d3c1ed2414ef72048f5ad640"

inherit cargo cargo-update-recipe-crates

PV = "0.3.2+git"
SRC_URI = "git://github.com/containers/podlet.git;protocol=https;branch=main"
SRCREV = "faf7c0d316851298dfb184ae1e7ff3289730a6ed"

require ${BPN}-crates.inc

BBCLASSEXTEND = "native nativesdk"
