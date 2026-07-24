DESCRIPTION = "An implementation of docker-compose with podman backend"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=b234ee4d69f5fce4486a80fdaf4a4263"

inherit python_setuptools_build_meta

PV = "1.5.0+git"
SRC_URI = "git://github.com/containers/podman-compose.git;branch=main;protocol=https"

SRCREV = "f7eeda1a3db10952424af6a5b0501c269ebe3f0d"

DEPENDS += "python3-pyyaml-native"

RDEPENDS:${PN} += "\
    python3-asyncio \
    python3-dotenv \
    python3-json \
    python3-pyyaml \
    python3-unixadmin \
"
