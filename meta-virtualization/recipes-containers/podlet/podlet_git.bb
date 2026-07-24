SUMMARY = "Generator for quadlet files"
DESCRIPTION = "Podlet generates Podman Quadlet files from a Podman command, compose file, or existing object."
LICENSE = "MPL-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=f75d2927d3c1ed2414ef72048f5ad640"

inherit cargo cargo-update-recipe-crates

PV = "0.3.16"
SRC_URI = "git://github.com/containers/podlet.git;protocol=https;branch=main"
SRCREV = "ca463af859931a9a43688d869eae5fe3a95e7143"

require ${BPN}-crates.inc

BBCLASSEXTEND = "native nativesdk"
