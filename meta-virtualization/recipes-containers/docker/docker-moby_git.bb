HOMEPAGE = "http://www.docker.com"
SUMMARY = "Linux container runtime"
DESCRIPTION = "Linux container runtime \
 Docker complements kernel namespacing with a high-level API which \
 operates at the process level. It runs unix processes with strong \
 guarantees of isolation and repeatability across servers. \
 . \
 Docker is a great building block for automating distributed systems: \
 large-scale web deployments, database clusters, continuous deployment \
 systems, private PaaS, service-oriented architectures, etc. \
 . \
 This package contains the daemon and client, which are \
 officially supported on x86_64 and arm hosts. \
 Other architectures are considered experimental. \
 . \
 Also, note that kernel version 3.10 or above is required for proper \
 operation of the daemon process, and that any lower versions may have \
 subtle and/or glaring issues. \
 "

# Notes:
#   - This docker variant uses moby and the other individually maintained
#     upstream variants for SRCREVs
#   - It is a true community / upstream tracking build, and is not a
#     docker curated set of commits or additions
#   - The version number on this package tracks the versions assigned to
#     the curated docker-ce repository. This allows compatibility and
#     functional equivalence, while allowing new features to be more
#     easily added.
#   - The common components of this recipe and docker-ce do need to be moved
#     to a docker.inc recipe
#
# Packaging details:
#
# https://github.com/docker/docker-ce-packaging.git
#  common.mk:
#    DOCKER_CLI_REPO    ?= https://github.com/docker/cli.git
#    DOCKER_ENGINE_REPO ?= https://github.com/docker/docker.git
#    REF                ?= HEAD
#    DOCKER_CLI_REF     ?= $(REF)
#    DOCKER_ENGINE_REF  ?= $(REF)
#
# These follow the tags for our releases in the listed repositories
# so we get that tag, and make it our SRCREVS:
#

SRCREV_moby = "a926bec8fc91332410133b24f3e9e3f5add13b48"
SRCREV_libnetwork = "3797618f9a38372e8107d8c06f6ae199e1133ae8"
SRCREV_cli = "43987fca488a535d810c429f75743d8c7b63bf4f"
SRCREV_FORMAT = "moby_libnetwork"
SRC_URI = "\
	git://github.com/moby/moby.git;branch=25.0;name=moby;protocol=https \
	git://github.com/docker/libnetwork.git;branch=master;name=libnetwork;destsuffix=git/libnetwork;protocol=https \
	git://github.com/docker/cli;branch=25.0;name=cli;destsuffix=git/cli;protocol=https \
	file://docker.init \
	file://0001-libnetwork-use-GO-instead-of-go.patch \
        file://0001-cli-use-external-GO111MODULE-and-cross-compiler.patch \
        file://0001-dynbinary-use-go-cross-compiler.patch;patchdir=src/import \
		file://CVE-2026-33997.patch;patchdir=src/import \
		file://CVE-2026-34040_p1.patch;patchdir=src/import \
		file://CVE-2026-34040_p2.patch;patchdir=src/import \
		file://CVE-2026-41568.patch;patchdir=src/import \
		file://CVE-2026-42306_p1.patch;patchdir=src/import \
		file://CVE-2026-42306_p2.patch;patchdir=src/import \
	"

DOCKER_COMMIT = "${SRCREV_moby}"

require docker.inc

# Apache-2.0 for docker
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://src/import/LICENSE;md5=4859e97a9c7780e77972d989f0823f28"

DOCKER_VERSION = "25.0.9"
PV = "${DOCKER_VERSION}+git${SRCREV_moby}"

CVE_PRODUCT = "docker mobyproject:moby"
