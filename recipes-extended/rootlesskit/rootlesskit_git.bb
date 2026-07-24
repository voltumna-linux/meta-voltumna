HOMEPAGE = "https://github.com/rootless-containers/rootlesskit"
SUMMARY =  "RootlessKit: Linux-native fakeroot using user namespaces"
DESCRIPTION = "RootlessKit is a Linux-native implementation of 'fake root' using user_namespaces(7). \
The purpose of RootlessKit is to run Docker and Kubernetes as an unprivileged user (known as 'Rootless mode'),\
so as to protect the real root on the host from potential container-breakout attacks. \
"

DEPENDS = " \
    go-md2man \
"

SRCREV_rootless = "a313ce81e9e48c49a409208b750baea967836b18"
SRCREV_FORMAT = "rootless"

SRC_URI = "git://github.com/rootless-containers/rootlesskit;name=rootless;branch=master;protocol=https;destsuffix=${GO_SRCURI_DESTSUFFIX} \
           file://0001-rootlesskit-add-GOFLAGS-to-Makefile.patch \
          "


# GO_MOD_FETCH_MODE: "vcs" (all git://) or "hybrid" (gomod:// + git://)
GO_MOD_FETCH_MODE ?= "hybrid"

# VCS mode: all modules via git://
include ${@ "go-mod-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}
include ${@ "go-mod-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}

# Hybrid mode: gomod:// for most, git:// for selected
include ${@ "go-mod-hybrid-gomod.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://src/import/LICENSE;md5=3b83ef96387f14655fc854ddc3c6bd57"

GO_IMPORT = "import"

PV = "v3.0.0-alpha.1+git"

ROOTLESS_PKG = "github.com/rootless-containers/rootlesskit"

# go-mod-discovery configuration
GO_MOD_DISCOVERY_BUILD_TARGET = "./cmd/..."
GO_MOD_DISCOVERY_GIT_REPO = "https://github.com/rootless-containers/rootlesskit.git"
GO_MOD_DISCOVERY_GIT_REF = "${SRCREV_rootless}"

inherit go goarch
inherit systemd pkgconfig
inherit go-mod-discovery

BB_GIT_SHALLOW = "1"

do_configure[noexec] = "1"

EXTRA_OEMAKE = " \
     PREFIX=${prefix} BINDIR=${bindir} LIBEXECDIR=${libexecdir} \
     ETCDIR=${sysconfdir} TMPFILESDIR=${nonarch_libdir}/tmpfiles.d \
     SYSTEMDDIR=${systemd_unitdir}/system USERSYSTEMDDIR=${systemd_unitdir}/user \
"

PACKAGECONFIG ?= ""

do_compile() {
	cd ${S}/src/import

	# GOMODCACHE, GOPROXY, GOSUMDB, GOTOOLCHAIN are set by go-mod-vcs.bbclass
	export GOPATH="${S}/src/import/.gopath:${STAGING_DIR_TARGET}/${prefix}/local/go"
	export CGO_ENABLED="1"

	# Pass the needed cflags/ldflags so that cgo
	# can find the needed headers files and libraries
	export GOARCH=${TARGET_GOARCH}
	export GOFLAGS="-trimpath"
	export CGO_CFLAGS="${CFLAGS} --sysroot=${STAGING_DIR_TARGET}"
	export CGO_LDFLAGS="${LDFLAGS} --sysroot=${STAGING_DIR_TARGET}"

	oe_runmake GO=${GO} BUILDTAGS="${BUILDTAGS}" all
}

do_install() {
	install -d "${D}${BIN_PREFIX}${base_bindir}"
	for b in rootlessctl  rootlesskit  rootlesskit-docker-proxy; do
		install -m 755 "${S}/src/import/bin/$b" "${D}${BIN_PREFIX}${base_bindir}"
	done
}
