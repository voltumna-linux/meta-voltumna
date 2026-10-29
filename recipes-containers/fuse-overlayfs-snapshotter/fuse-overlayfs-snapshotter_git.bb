SUMMARY = "fuse-overlayfs snapshotter plugin for containerd"
DESCRIPTION = "containerd proxy snapshotter plugin implementing the overlay \
semantics with fuse-overlayfs, allowing the containerd image store to run \
on filesystems without kernel overlayfs support (NFS, UBIFS)."

HOMEPAGE = "https://github.com/containerd/fuse-overlayfs-snapshotter"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://src/import/LICENSE;md5=1269f40c0d099c21a871163984590d89"

RDEPENDS:${PN} = "fuse-overlayfs"

# Directory holding the snapshotter's persistent store
CONTAINERD_FUSE_OVERLAYFS_ROOT ?= "${localstatedir}/lib/containerd-fuse-overlayfs"

SRCREV_snapshotter = "da57796c7d0a2b608abf173651cf148706e33337"
SRCREV_FORMAT = "snapshotter"

SRC_URI = "git://github.com/containerd/fuse-overlayfs-snapshotter;protocol=https;nobranch=1;name=snapshotter;destsuffix=${GO_SRCURI_DESTSUFFIX} \
           file://containerd-fuse-overlayfs.service \
           file://config.toml \
"

GO_MOD_FETCH_MODE ?= "hybrid"

# VCS mode: all modules via git://
include ${@ "go-mod-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}
include ${@ "go-mod-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}

# Hybrid mode: gomod:// for most, git:// for selected
include ${@ "go-mod-hybrid-gomod.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}

# Per-dependency license tracking
require go-mod-licenses.inc

GO_IMPORT = "import"

PV = "2.1.7"

# go-mod-discovery configuration
GO_MOD_DISCOVERY_BUILD_TARGET = "./cmd/containerd-fuse-overlayfs-grpc"
GO_MOD_DISCOVERY_LICENSE_TARGETS = "./cmd/containerd-fuse-overlayfs-grpc"
GO_MOD_DISCOVERY_GIT_REPO = "https://github.com/containerd/fuse-overlayfs-snapshotter.git"
GO_MOD_DISCOVERY_GIT_REF = "${SRCREV_snapshotter}"

inherit go goarch go-mod-discovery systemd

COMPATIBLE_HOST = "^(?!mips).*"

do_configure[noexec] = "1"

do_compile() {
	cd ${S}/src/import

	export GOPATH="${S}/src/import/.gopath:${STAGING_DIR_TARGET}/${prefix}/local/go"

	# cgo is required on 32-bit targets: GOBUILDFLAGS contains
	# -buildmode=pie (added by the go class to satisfy the textrel QA
	# check), and buildmode=pie needs external linking there. Pass the
	# needed cflags/ldflags so that cgo can find the needed headers
	# files and libraries.
	export CGO_ENABLED="1"
	export CGO_CFLAGS="${CFLAGS}"
	export CGO_LDFLAGS="${LDFLAGS}"
	export GOARCH=${TARGET_GOARCH}

	mkdir -p ./bin
	${GO} build ${GOBUILDFLAGS} -o ./bin/containerd-fuse-overlayfs-grpc ./cmd/containerd-fuse-overlayfs-grpc
}

do_install() {
	install -d ${D}${bindir}
	install -m 0755 ${S}/src/import/bin/containerd-fuse-overlayfs-grpc ${D}${bindir}

	if ${@bb.utils.contains('DISTRO_FEATURES','systemd','true','false',d)}; then
		install -d ${D}${systemd_system_unitdir}
		install -m 0644 ${UNPACKDIR}/containerd-fuse-overlayfs.service ${D}${systemd_system_unitdir}
		sed -i -e "s|@CONTAINERD_FUSE_OVERLAYFS_ROOT@|${CONTAINERD_FUSE_OVERLAYFS_ROOT}|g" \
			${D}${systemd_system_unitdir}/containerd-fuse-overlayfs.service
	fi

	install -d ${D}${docdir}/${PN}
	install -m 0644 ${UNPACKDIR}/config.toml ${D}${docdir}/${PN}/config.toml

	install -d ${D}${sysconfdir}/tmpfiles.d
	echo "d ${CONTAINERD_FUSE_OVERLAYFS_ROOT} 0700 root root - -" > ${D}${sysconfdir}/tmpfiles.d/containerd-fuse-overlayfs.conf
}

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "containerd-fuse-overlayfs.service"

FILES:${PN} += " \
    ${systemd_system_unitdir}/containerd-fuse-overlayfs.service \
    ${docdir}/${PN}/config.toml \
    ${sysconfdir}/tmpfiles.d/containerd-fuse-overlayfs.conf \
"
