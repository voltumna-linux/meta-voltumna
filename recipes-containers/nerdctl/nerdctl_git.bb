HOMEPAGE = "https://github.com/containerd/nerdctl"
SUMMARY =  "Docker-compatible CLI for containerd"
DESCRIPTION = "nerdctl: Docker-compatible CLI for containerd \
    "

DEPENDS = " \
    go-md2man \
    rsync-native \
    ${@bb.utils.filter('DISTRO_FEATURES', 'systemd', d)} \
"

SRCREV_FORMAT = "nerdcli"
SRCREV_nerdcli = "0d1089396f017bb872ad40606b0d31ebdeaa828a"

SRC_URI = "git://github.com/containerd/nerdctl.git;name=nerdcli;branch=release/2.2;protocol=https;destsuffix=${GO_SRCURI_DESTSUFFIX}"

# Upstream repo deleted from GitHub - fetch via Go module proxy instead
SRC_URI += "gomod://github.com/vtolstov/go-ioctl;version=v0.0.0-20151206205506-6be9cced4810;sha256sum=26e96d5eb3389453eb54f8e510676f3dabda93deb842f679f2e967052754c4de"
GO_MOD_VCS_EXCLUDE = "github.com/vtolstov/go-ioctl"

# GO_MOD_FETCH_MODE: "vcs" (all git://) or "hybrid" (gomod:// + git://)
GO_MOD_FETCH_MODE ?= "hybrid"

# VCS mode: all modules via git://
include ${@ "go-mod-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}
include ${@ "go-mod-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}

# Hybrid mode: gomod:// for most, git:// for selected
include ${@ "go-mod-hybrid-gomod.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}

# patches
SRC_URI += " \
            file://0001-Makefile-allow-external-specification-of-build-setti.patch \
           "

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://src/import/LICENSE;md5=3b83ef96387f14655fc854ddc3c6bd57"

GO_IMPORT = "import"

PV = "v2.2.1"

NERDCTL_PKG = "github.com/containerd/nerdctl"

# go-mod-discovery configuration
GO_MOD_DISCOVERY_BUILD_TARGET = "./cmd/nerdctl"
GO_MOD_DISCOVERY_GIT_REPO = "https://github.com/containerd/nerdctl.git"
GO_MOD_DISCOVERY_GIT_REF = "${SRCREV_nerdcli}"

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
        export GOPATH="${S}/src/import/.gopath:${S}/src/import/vendor:${STAGING_DIR_TARGET}/${prefix}/local/go"
        export GOMODCACHE="${S}/pkg/mod"
        export CGO_ENABLED="1"
        export GOSUMDB="off"
        export GOTOOLCHAIN="local"
        export GOPROXY="off"

        cd ${S}/src/import

        # Pass the needed cflags/ldflags so that cgo
        # can find the needed headers files and libraries
        export GOARCH=${TARGET_GOARCH}
        export CGO_CFLAGS="${CFLAGS}"
        export CGO_LDFLAGS="${LDFLAGS}"

        # -trimpath removes build paths from the binary (required for reproducible builds)
        oe_runmake GO=${GO} BUILDTAGS="${BUILDTAGS}" GO_BUILD_FLAGS="-trimpath -buildmode=pie" binaries
}

do_install() {
        install -d "${D}${BIN_PREFIX}${base_bindir}"
        install -m 755 "${S}/src/import/_output/nerdctl" "${D}${BIN_PREFIX}${base_bindir}"
}

INHIBIT_PACKAGE_STRIP = "1"
INSANE_SKIP:${PN} += "ldflags already-stripped"

