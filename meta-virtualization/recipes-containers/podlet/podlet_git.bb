SUMMARY = "Generator for quadlet files"
DESCRIPTION = "Podlet generates Podman Quadlet files from a Podman command, compose file, or existing object."
LICENSE = "MPL-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=f75d2927d3c1ed2414ef72048f5ad640"

inherit cargo cargo-update-recipe-crates

PV = "0.3.2+git"
SRC_URI = "git://github.com/containers/podlet.git;protocol=https;branch=main"
SRCREV = "74ba158ee3b96e215c3aa74e8b64d2f39903fb9a"

require ${BPN}-crates.inc

BBCLASSEXTEND = "native nativesdk"
