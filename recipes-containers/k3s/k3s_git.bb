SUMMARY = "Production-Grade Container Scheduling and Management"
DESCRIPTION = "Lightweight Kubernetes, intended to be a fully compliant Kubernetes."
HOMEPAGE = "https://k3s.io/"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${S}/src/import/LICENSE;md5=2ee41112a44fe7014dce33e26468ba93"

SRC_URI = "git://github.com/rancher/k3s.git;branch=release-1.35;name=k3s;protocol=https;destsuffix=${GO_SRCURI_DESTSUFFIX} \
           file://k3s.service \
           file://k3s-agent.service \
           file://k3s-agent \
           file://k3s-clean \
           file://cni-flannel.conflist \
           file://k3s-killall.sh \
           file://k3s-role-setup.sh \
           file://k3s-role-setup.service \
           file://k3s-get-token.sh \
           file://10-k3s-cluster.network \
          "

# Traefik Helm charts — downloaded and embedded into the k3s binary
# so they can be served via the k3s static chart endpoint at runtime.
# Opt-in via PACKAGECONFIG since traefik is not needed for basic k3s
# operation and the chart images must be pullable at runtime.
TRAEFIK_CHART_VERSION = "39.0.501+up39.0.5"
SRC_URI += "${@bb.utils.contains('PACKAGECONFIG', 'traefik', \
    'https://k3s.io/k3s-charts/assets/traefik-crd/traefik-crd-${TRAEFIK_CHART_VERSION}.tgz;name=traefik-crd;unpack=0;subdir=charts \
     https://k3s.io/k3s-charts/assets/traefik/traefik-${TRAEFIK_CHART_VERSION}.tgz;name=traefik;unpack=0;subdir=charts', \
    '', d)}"
SRC_URI[traefik-crd.sha256sum] = "c6245bdcfd193d10ec956d90c50e0d1a3fa1bde541df80744e72eee91b054640"
SRC_URI[traefik.sha256sum] = "888de9d098769b9199238076bee225d1b10dba1e889b0e28127eddc38cdb435b"

SRC_URI[k3s.md5sum] = "363d3a08dc0b72ba6e6577964f6e94a5"
SRCREV_k3s = "4841276da0cf9f6f3e323b6cc8b10da381331f98"

SRCREV_FORMAT = "k3s_fuse"
PV = "v1.35.2+k3s1+git"

# K3s uses flannel for CNI networking, not the containerd bridge config
CNI_NETWORKING_FILES ?= "${UNPACKDIR}/cni-flannel.conflist"

# Claim the cluster network interface (eth1) so systemd-networkd's
# default catch-all doesn't configure it with DHCP. The static IP
# is set at boot by k3s-role-setup.service via a networkd drop-in.
VIRT_NETWORKING_FILES ?= "${UNPACKDIR}/10-k3s-cluster.network"

PACKAGECONFIG ??= "traefik"
PACKAGECONFIG[traefik] = ",,,"

# Build tags - used by both do_compile and do_discover_modules
TAGS = "static_build netcgo osusergo providerless"

# go-mod-discovery configuration
# Uses defaults: SRCDIR=${S}/src/import, BUILD_TAGS=${TAGS}, GOPATH=${S}/src/import/.gopath:...
GO_MOD_DISCOVERY_BUILD_TARGET = "./cmd/server/main.go"
GO_MOD_DISCOVERY_LDFLAGS = "-X github.com/k3s-io/k3s/pkg/version.Version=${PV} -w -s"
GO_MOD_DISCOVERY_GIT_REPO = "https://github.com/rancher/k3s.git"
GO_MOD_DISCOVERY_GIT_REF = "${SRCREV_k3s}"

# GO_MOD_FETCH_MODE: "vcs" (all git://) or "hybrid" (gomod:// + git://)
GO_MOD_FETCH_MODE ?= "hybrid"

# VCS mode: all modules via git://
include ${@ "go-mod-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}
include ${@ "go-mod-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}

# Hybrid mode: gomod:// for most, git:// for selected
include ${@ "go-mod-hybrid-gomod.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}

inherit go
inherit goarch
inherit systemd
inherit cni_networking
inherit virt_networking
inherit go-mod-discovery

BB_GIT_SHALLOW = "1"

COMPATIBLE_HOST = "^(?!mips).*"

PACKAGECONFIG = ""
PACKAGECONFIG[upx] = ",,upx-native"
GO_IMPORT = "import"
GO_BUILD_LDFLAGS = "-X github.com/k3s-io/k3s/pkg/version.Version=${PV} \
                    -X github.com/k3s-io/k3s/pkg/version.GitCommit=${@d.getVar('SRCREV_k3s', d, 1)[:8]} \
                    -w -s \
                   "
BIN_PREFIX ?= "${exec_prefix}/local"

inherit features_check
REQUIRED_DISTRO_FEATURES ?= "seccomp"

DEPENDS += "rsync-native"

# Go's PIE builds pull in cgo objects that still require text relocations.
# Explicitly allow them at link time to avoid ld --fatal-warnings aborting the build.
GO_EXTRA_LDFLAGS:append = " -Wl,-z,notext"

do_compile() {
        export GOPATH="${S}/src/import/.gopath:${S}/src/import/vendor:${STAGING_DIR_TARGET}/${prefix}/local/go"
        export GOMODCACHE="${S}/pkg/mod"
        export CGO_ENABLED="1"
        export GOSUMDB="off"
        export GOTOOLCHAIN="local"
        export GOPROXY="off"

        # Remove go.sum files from git-fetched dependencies to prevent checksum conflicts
        # Our git-built modules have different checksums than proxy.golang.org tarballs
        find ${WORKDIR}/sources/vcs_cache -name "go.sum" -delete || true

        cd ${S}/src/import

        # go.mod and go.sum are synchronized by do_sync_go_files task
        # No manual fixes needed - discovery and recipe generation handle version matching

        # Populate embed directories before build — upstream scripts/build
        # does this to embed manifests and static content into the binary
        # via go:embed. Without this, k3s's deploy.Stage() has no manifests
        # to process and system components (coredns, metrics-server, etc.)
        # are not deployed on first server start.
        cp -a manifests/* pkg/deploy/embed/

        # Embed traefik Helm charts if enabled via PACKAGECONFIG
        if ${@bb.utils.contains('PACKAGECONFIG', 'traefik', 'true', 'false', d)}; then
            mkdir -p pkg/static/embed/charts
            cp -a ${WORKDIR}/sources/charts/traefik-crd-${TRAEFIK_CHART_VERSION}.tgz pkg/static/embed/charts/
            cp -a ${WORKDIR}/sources/charts/traefik-${TRAEFIK_CHART_VERSION}.tgz pkg/static/embed/charts/
        fi

        VERSION_GOLANG="$(go version | cut -d" " -f3)"
        ${GO} build -trimpath -tags "${TAGS}" -ldflags "-X github.com/k3s-io/k3s/pkg/version.UpstreamGolang=$VERSION_GOLANG  ${GO_BUILD_LDFLAGS} -w -s" -o ./dist/artifacts/k3s ./cmd/server/main.go

        # Use UPX if it is enabled (and thus exists) to compress binary
        if command -v upx > /dev/null 2>&1; then
                upx -9 ./dist/artifacts/k3s
        fi
}

do_install() {
        install -d "${D}${BIN_PREFIX}/bin"
        install -m 755 "${S}/src/import/dist/artifacts/k3s" "${D}${BIN_PREFIX}/bin"
        ln -sr "${D}/${BIN_PREFIX}/bin/k3s" "${D}${BIN_PREFIX}/bin/crictl"
        # We want to use the containerd provided ctr
        # ln -sr "${D}/${BIN_PREFIX}/bin/k3s" "${D}${BIN_PREFIX}/bin/ctr"
        ln -sr "${D}/${BIN_PREFIX}/bin/k3s" "${D}${BIN_PREFIX}/bin/kubectl"
        install -m 755 "${UNPACKDIR}/k3s-clean" "${D}${BIN_PREFIX}/bin"
        install -m 755 "${UNPACKDIR}/k3s-killall.sh" "${D}${BIN_PREFIX}/bin"

        if ${@bb.utils.contains('DISTRO_FEATURES','systemd','true','false',d)}; then
                install -D -m 0644 "${UNPACKDIR}/k3s.service" "${D}${systemd_system_unitdir}/k3s.service"
                install -D -m 0644 "${UNPACKDIR}/k3s-agent.service" "${D}${systemd_system_unitdir}/k3s-agent.service"
                install -D -m 0644 "${UNPACKDIR}/k3s-role-setup.service" "${D}${systemd_system_unitdir}/k3s-role-setup.service"
                sed -i "s#\(Exec\)\(.*\)=\(.*\)\(k3s\)#\1\2=${BIN_PREFIX}/bin/\4#g" "${D}${systemd_system_unitdir}/k3s.service" "${D}${systemd_system_unitdir}/k3s-agent.service"
                install -m 755 "${UNPACKDIR}/k3s-agent" "${D}${BIN_PREFIX}/bin"
                install -m 755 "${UNPACKDIR}/k3s-role-setup.sh" "${D}${BIN_PREFIX}/bin/k3s-role-setup.sh"
                install -m 755 "${UNPACKDIR}/k3s-get-token.sh" "${D}${BIN_PREFIX}/bin/k3s-get-token"
        fi

	mkdir -p ${D}${datadir}/k3s/
	install -m 0755 ${S}/src/import/contrib/util/check-config.sh ${D}${datadir}/k3s/

	# Create server manifests directory — k3s's deploy.Stage() writes
	# processed manifests here at runtime (template variables substituted)
	install -d "${D}/var/lib/rancher/k3s/server/manifests"

	# Install default k3s config — disable traefik if not in PACKAGECONFIG
	install -d "${D}${sysconfdir}/rancher/k3s"
	echo "# k3s server configuration (generated by recipe)" \
		> "${D}${sysconfdir}/rancher/k3s/config.yaml"
	echo "disable-cloud-controller: true" \
		>> "${D}${sysconfdir}/rancher/k3s/config.yaml"
	if ! ${@bb.utils.contains('PACKAGECONFIG', 'traefik', 'true', 'false', d)}; then
		echo "disable:" >> "${D}${sysconfdir}/rancher/k3s/config.yaml"
		echo "  - traefik" >> "${D}${sysconfdir}/rancher/k3s/config.yaml"
	fi
}

PACKAGES =+ "${PN}-server ${PN}-agent"

SYSTEMD_PACKAGES = "${@bb.utils.contains('DISTRO_FEATURES','systemd','${PN}-server ${PN}-agent ${PN}','',d)}"
SYSTEMD_SERVICE:${PN}-server = "${@bb.utils.contains('DISTRO_FEATURES','systemd','k3s.service','',d)}"
SYSTEMD_SERVICE:${PN}-agent = "${@bb.utils.contains('DISTRO_FEATURES','systemd','k3s-agent.service','',d)}"
SYSTEMD_SERVICE:${PN} = "${@bb.utils.contains('DISTRO_FEATURES','systemd','k3s-role-setup.service','',d)}"
SYSTEMD_AUTO_ENABLE:${PN}-agent = "disable"

FILES:${PN}-agent = "${BIN_PREFIX}/bin/k3s-agent"
FILES:${PN} += "${BIN_PREFIX}/bin/* /var/lib/rancher/k3s/server/manifests ${sysconfdir}/rancher/k3s"

RDEPENDS:${PN} = "k3s-cni conntrack-tools coreutils findutils iptables iproute2 ipset virtual-containerd"
RDEPENDS:${PN}-server = "${PN}"
RDEPENDS:${PN}-agent = "${PN}"

RRECOMMENDS:${PN} = "\
                     kernel-module-xt-addrtype \
                     kernel-module-xt-nat \
                     kernel-module-xt-multiport \
                     kernel-module-xt-conntrack \
                     kernel-module-xt-comment \
                     kernel-module-xt-mark \
                     kernel-module-xt-connmark \
                     kernel-module-vxlan \
                     kernel-module-xt-masquerade \
                     kernel-module-xt-statistic \
                     kernel-module-xt-physdev \
                     kernel-module-xt-nflog \
                     kernel-module-xt-limit \
                     kernel-module-nfnetlink-log \
                     kernel-module-ip-vs \
                     kernel-module-ip-vs-rr \
                     kernel-module-ip-vs-sh \
                     kernel-module-ip-vs-wrr \
                     "

RCONFLICTS:${PN} = "kubectl"

PACKAGES =+ "${PN}-contrib"
FILES:${PN}-contrib += "${datadir}/k3s/check-config.sh"
RDEPENDS:${PN}-contrib += "bash"

INHIBIT_PACKAGE_STRIP = "1"
INSANE_SKIP:${PN} += "ldflags already-stripped textrel"
