SUMMARY = "Incus system container and virtual machine manager"
DESCRIPTION = "Incus is a modern, secure and powerful system container and \
virtual machine manager. It is the community fork of Canonical LXD, providing \
a unified experience for running and managing containers and VMs."
HOMEPAGE = "https://linuxcontainers.org/incus/"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${S}/COPYING;md5=3b83ef96387f14655fc854ddc3c6bd57"

SRC_URI = "git://github.com/lxc/incus.git;branch=stable-6.0;name=incus;protocol=https \
           file://incus.service \
           file://incus.socket \
           "

SRCREV_incus = "5231e7a1beca905d57208b441040f9ebdc6a2c6f"
SRCREV_FORMAT = "incus"
PV = "6.0.6+git"

COMPATIBLE_HOST = "(x86_64|aarch64).*-linux"

GO_IMPORT = "github.com/lxc/incus/v6"

DEPENDS = "cowsql raft lxc sqlite3 libuv libcap acl"

# Build tags — libsqlite3 enables cowsql/sqlite3 CGO bindings
TAGS = "libsqlite3"

# go-mod-discovery configuration
GO_MOD_DISCOVERY_SRCDIR = "${S}"
GO_MOD_DISCOVERY_BUILD_TARGET = "./cmd/incus-migrate"
GO_MOD_DISCOVERY_BUILD_TAGS = "netgo"
GO_MOD_DISCOVERY_LDFLAGS = "-w -s"
GO_MOD_DISCOVERY_GIT_REPO = "https://github.com/lxc/incus.git"
GO_MOD_DISCOVERY_GIT_REF = "${SRCREV_incus}"
GO_MOD_DISCOVERY_SKIP_VERIFY = "1"

GO_MOD_FETCH_MODE ?= "hybrid"

# Hybrid mode: gomod:// for most, git:// for selected
include ${@ "go-mod-hybrid-gomod.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}

# VCS mode: all modules via git://
include ${@ "go-mod-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}
include ${@ "go-mod-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}

inherit go goarch pkgconfig systemd go-mod-discovery

INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
INSANE_SKIP:${PN} += "already-stripped"

# Disable CGO during discovery (uses pure-Go incus-migrate target)
CGO_ENABLED:task-discover-modules = "0"
CGO_ENABLED:task-discover-and-generate = "0"

PACKAGECONFIG ??= ""
PACKAGECONFIG[vm] = ",,,qemu virtiofsd ovmf"

RDEPENDS:${PN} = " \
    lxc \
    lxcfs \
    cowsql \
    raft \
    attr \
    acl \
    dnsmasq \
    iptables \
    rsync \
    squashfs-tools \
    tar \
    xz \
    shadow \
"

inherit useradd

USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "-r incus-admin"

pkg_postinst:${PN}() {
    # Add subordinate uid/gid range for root if not already present.
    # Uses 1000000 base to avoid collision with podman/other rootless
    # runtimes which typically start at 100000.
    if [ -f $D${sysconfdir}/subuid ] && ! grep -q "^root:" $D${sysconfdir}/subuid; then
        echo "root:1000000:1000000000" >> $D${sysconfdir}/subuid
    elif [ ! -f $D${sysconfdir}/subuid ]; then
        echo "root:1000000:1000000000" > $D${sysconfdir}/subuid
    fi
    if [ -f $D${sysconfdir}/subgid ] && ! grep -q "^root:" $D${sysconfdir}/subgid; then
        echo "root:1000000:1000000000" >> $D${sysconfdir}/subgid
    elif [ ! -f $D${sysconfdir}/subgid ]; then
        echo "root:1000000:1000000000" > $D${sysconfdir}/subgid
    fi
}

do_compile() {
    cd ${S}

    export CGO_ENABLED=1
    export CGO_LDFLAGS_ALLOW="(-Wl,-wrap,pthread_create)|(-Wl,-z,now)"

    # Main daemon and client (CGO required, -buildmode=pie to avoid textrel)
    ${GO} build -buildmode=pie -trimpath -o ${B}/incusd -tags "libsqlite3" -ldflags "-w -s" ./cmd/incusd
    ${GO} build -buildmode=pie -trimpath -o ${B}/incus -tags "libsqlite3" -ldflags "-w -s" ./cmd/incus
    ${GO} build -buildmode=pie -trimpath -o ${B}/fuidshift -tags "libsqlite3" -ldflags "-w -s" ./cmd/fuidshift
    ${GO} build -buildmode=pie -trimpath -o ${B}/lxc-to-incus -tags "libsqlite3" -ldflags "-w -s" ./cmd/lxc-to-incus
    ${GO} build -buildmode=pie -trimpath -o ${B}/incus-benchmark -tags "libsqlite3" -ldflags "-w -s" ./cmd/incus-benchmark
    ${GO} build -buildmode=pie -trimpath -o ${B}/incus-user -tags "libsqlite3" -ldflags "-w -s" ./cmd/incus-user

    # Agent and migrate tool (pure Go, no CGO)
    CGO_ENABLED=0 ${GO} build -trimpath -o ${B}/incus-agent -tags "agent,netgo" -ldflags "-w -s" ./cmd/incus-agent
    CGO_ENABLED=0 ${GO} build -trimpath -o ${B}/incus-migrate -tags "netgo" -ldflags "-w -s" ./cmd/incus-migrate
}

SYSTEMD_SERVICE:${PN} = "incus.service incus.socket"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${bindir}
    install -d ${D}${sbindir}

    install -m 0755 ${B}/incus ${D}${bindir}/incus
    install -m 0755 ${B}/incusd ${D}${sbindir}/incusd
    install -m 0755 ${B}/incus-agent ${D}${bindir}/incus-agent
    install -m 0755 ${B}/incus-migrate ${D}${bindir}/incus-migrate
    install -m 0755 ${B}/fuidshift ${D}${bindir}/fuidshift
    install -m 0755 ${B}/lxc-to-incus ${D}${bindir}/lxc-to-incus
    install -m 0755 ${B}/incus-benchmark ${D}${bindir}/incus-benchmark
    install -m 0755 ${B}/incus-user ${D}${bindir}/incus-user

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/incus.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${UNPACKDIR}/incus.socket ${D}${systemd_system_unitdir}/

    # Create state directory expected by ConditionPathExists
    install -d ${D}/var/lib/incus

}
