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

SRCREV_moby = "1da6517e1a4381297e56862f6f373f265c28d102"
SRCREV_cli = "df016a3a9538efb6d7d6e7c3baf291dbbe28eee0"
SRCREV_FORMAT = "moby"
SRC_URI = "\
	git://github.com/moby/moby.git;nobranch=1;name=moby;protocol=https;destsuffix=${GO_SRCURI_DESTSUFFIX} \
	git://github.com/docker/cli;nobranch=1;name=cli;destsuffix=${BB_GIT_DEFAULT_DESTSUFFIX}/cli;protocol=https \
	file://docker.init \
        file://0001-cli-use-external-GO111MODULE-and-cross-compiler.patch \
        file://0001-dynbinary-use-go-cross-compiler.patch;patchdir=src/import \
        file://0001-check-config-make-CONFIG_MEMCG_SWAP-conditional.patch;patchdir=src/import \
        file://CVE-2026-41568.patch;patchdir=src/import \
        file://CVE-2026-42306_p1.patch;patchdir=src/import \
        file://CVE-2026-42306_p2.patch;patchdir=src/import \
	"

DOCKER_COMMIT = "${SRCREV_moby}"

require docker.inc

# Apache-2.0 for docker
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://src/import/LICENSE;md5=4859e97a9c7780e77972d989f0823f28"

DOCKER_VERSION = "v29.3.0"
PV = "${DOCKER_VERSION}+git${SRCREV_moby}"

CVE_PRODUCT = "docker mobyproject:moby"
