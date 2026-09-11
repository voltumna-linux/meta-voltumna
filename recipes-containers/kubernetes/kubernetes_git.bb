HOMEPAGE = "git://github.com/kubernetes/kubernetes;branch=master;protocol=https"
SUMMARY = "Production-Grade Container Scheduling and Management"
DESCRIPTION = "Kubernetes is an open source system for managing containerized \
applications across multiple hosts, providing basic mechanisms for deployment, \
maintenance, and scaling of applications. \
"

PV = "1.36.4+git"
CVE_VERSION = "1.36.4"
SRCREV_kubernetes = "ed15c228276ffddb7900bcee5be7e5fd18623810"
SRCREV_kubernetes-release = "c28e997b56a39695b0623c2b7d757cf27251df94"
PE = "1"

BBCLASSEXTEND = "devupstream:target"
LIC_FILES_CHKSUM:class-devupstream = "file://LICENSE;md5=3b83ef96387f14655fc854ddc3c6bd57"
DEFAULT_PREFERENCE:class-devupstream = "-1"
SRC_URI:class-devupstream = "git://github.com/kubernetes/kubernetes.git;branch=release-1.36;name=kubernetes;protocol=https \
                             git://github.com/kubernetes/release;branch=master;name=kubernetes-release;destsuffix=${BB_GIT_DEFAULT_DESTSUFFIX}/release;protocol=https \
                            "
SRCREV_kubernetes:class-devupstream = "ed15c228276ffddb7900bcee5be7e5fd18623810"
SRCREV_kubernetes-release:class-devupstream = "c28e997b56a39695b0623c2b7d757cf27251df94"
PV:class-devupstream = "1.36.4+git${SRCREV_kubernetes}"

SRCREV_FORMAT ?= "kubernetes_release"

SRC_URI = "git://github.com/kubernetes/kubernetes.git;branch=release-1.36;name=kubernetes;protocol=https;destsuffix=${BB_GIT_DEFAULT_DESTSUFFIX}/src/github.com/kubernetes/kubernetes \
           git://github.com/kubernetes/release;branch=master;name=kubernetes-release;destsuffix=${BB_GIT_DEFAULT_DESTSUFFIX}/release;protocol=https"

SRC_URI:append = " \
           file://0001-hack-lib-golang.sh-use-CC-from-environment.patch \
           file://0001-cross-don-t-build-tests-by-default.patch \
           file://0001-build-golang.sh-convert-remaining-go-calls-to-use.patch \
           file://0001-build-hack-allow-go-1.20-building.patch \
           file://00_cni-containerd-net.conflist \
           file://k8s-init \
           file://99-kubernetes.conf \
          "

DEPENDS += "rsync-native \
            coreutils-native \
            go-native \
           "

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3b83ef96387f14655fc854ddc3c6bd57"

GO_IMPORT = "import"
S = "${UNPACKDIR}/${BB_GIT_DEFAULT_DESTSUFFIX}/src/github.com/kubernetes/kubernetes"

inherit systemd
inherit go
inherit goarch
inherit cni_networking

COMPATIBLE_HOST = '(x86_64.*|arm.*|aarch64.*)-linux'

CGO_LDFLAGS ?= "${LDFLAGS}"
CGO_LDFLAGS:remove = "${DEBUG_PREFIX_MAP}"

do_compile() {
	export GOPATH="${S}/src/import/.gopath:${S}/src/import/vendor:${STAGING_DIR_TARGET}/${prefix}/local/go:${UNPACKDIR}/git/"
	cd ${S}

	# Build the host tools first, using the host compiler
	export GOARCH="${BUILD_GOARCH}"
	# Pass the needed cflags/ldflags so that cgo can find the needed headers files and libraries
	export CGO_ENABLED="1"
	export CFLAGS="${BUILD_CFLAGS}"
	export LDFLAGS="${BUILD_LDFLAGS}"
	export CGO_CFLAGS="${BUILD_CFLAGS}"
	# as of go 1.15.5, there are some flags the CGO doesn't like. Rather than
	# clearing them all, we sed away the ones we don't want.
	export CGO_LDFLAGS="$(echo ${BUILD_LDFLAGS} | sed 's/-Wl,-O1//g' | sed 's/-Wl,--dynamic-linker.*?\( \|$\)//g')"
	export CC="${BUILD_CC}"
	export LD="${BUILD_LD}"

	# set the toolchain to local to avoid an attempted fetch of
	# valiation by the build
	# https://github.com/actions/setup-go/issues/420
	export GOTOOLCHAIN="local"

	# make generated_files GO="go" KUBE_BUILD_PLATFORMS="${HOST_GOOS}/${BUILD_GOARCH}"
	# is replaced by:
	# ./hack/update-codegen.sh
	# but we don't appear to need either anymore, but we leave them as a placeholder/reminder

	# Build the target binaries
	export GOARCH="${TARGET_GOARCH}"
	# Pass the needed cflags/ldflags so that cgo can find the needed headers files and libraries
	export CGO_ENABLED="1"
	export CGO_CFLAGS="${CFLAGS}"
	export CGO_LDFLAGS="${LDFLAGS}"
	export CFLAGS=""
	export LDFLAGS=""
	export CC="${CC}"
	export LD="${LD}"
	export GOBIN=""
	export GOFLAGS="-trimpath"

	# to limit what is built, use 'WHAT', i.e. make WHAT=cmd/kubelet
	make cross CGO_FLAGS=${CGO_FLAGS} GO=${GO} KUBE_BUILD_PLATFORMS=${GOOS}/${GOARCH} GOLDFLAGS="" DBG=1
}

do_install() {
    install -d ${D}${bindir}
    install -d ${D}${systemd_unitdir}/system/
    install -d ${D}${systemd_unitdir}/system/kubelet.service.d/

    install -d ${D}${sysconfdir}/kubernetes/manifests/

    install -m 755 -D ${S}/_output/local/bin/${TARGET_GOOS}/${TARGET_GOARCH}/* ${D}/${bindir}

    # NOTE: kubernetes-release reorganized the templates tree: 'kubepkg' was
    # removed and 'krel' (the release tool) holds the templates now, in a
    # flatter layout without the deb/<pkg>/lib/systemd/system/ wrapping.
    install -m 0644 ${UNPACKDIR}/${BB_GIT_DEFAULT_DESTSUFFIX}/release/cmd/krel/templates/latest/kubelet/kubelet.service ${D}${systemd_unitdir}/system/
    install -m 0644 ${UNPACKDIR}/${BB_GIT_DEFAULT_DESTSUFFIX}/release/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf ${D}${systemd_unitdir}/system/kubelet.service.d/

    if ${@bb.utils.contains('DISTRO_FEATURES','systemd','true','false',d)}; then
	install -d "${D}${BIN_PREFIX}${base_bindir}"
	install -m 755 "${UNPACKDIR}/k8s-init" "${D}${BIN_PREFIX}${base_bindir}"

	install -d ${D}${sysconfdir}/sysctl.d
	install -m 0644 "${UNPACKDIR}/99-kubernetes.conf" "${D}${sysconfdir}/sysctl.d"
    fi
}

CNI_NETWORKING_FILES ?= "${UNPACKDIR}/00_cni-containerd-net.conflist"

PACKAGES =+ "kubeadm kubectl kubelet kube-proxy ${PN}-misc ${PN}-host"

ALLOW_EMPTY:${PN} = "1"
INSANE_SKIP:${PN} += "ldflags already-stripped"
INSANE_SKIP:${PN}-misc += "ldflags already-stripped textrel"
INSANE_SKIP:${MLPREFIX}kubelet += "ldflags already-stripped textrel"

# Note: we are explicitly *not* adding docker to the rdepends, since we allow
#       backends like cri-o to be used.
RDEPENDS:${PN} += "kubeadm \
                   kubectl \
                   kubelet \
                   kubernetes-cni"

RDEPENDS:kubeadm = "kubelet kubectl cri-tools conntrack-tools"
FILES:kubeadm = "${bindir}/kubeadm ${systemd_unitdir}/system/kubelet.service.d/*"

RDEPENDS:kubelet = "iptables socat util-linux ethtool iproute2 ebtables iproute2-tc"
FILES:kubelet = "${bindir}/kubelet ${systemd_unitdir}/system/kubelet.service ${sysconfdir}/kubernetes/manifests/"

SYSTEMD_PACKAGES = "${@bb.utils.contains('DISTRO_FEATURES','systemd','kubelet','',d)}"
SYSTEMD_SERVICE:kubelet = "${@bb.utils.contains('DISTRO_FEATURES','systemd','kubelet.service','',d)}"
SYSTEMD_AUTO_ENABLE:kubelet = "enable"

FILES:kubectl = "${bindir}/kubectl"
FILES:kube-proxy = "${bindir}/kube-proxy"
FILES:${PN}-misc = "${bindir} ${sysconfdir}/sysctl.d"

ALLOW_EMPTY:${PN}-host = "1"
FILES:${PN}-host = "${BIN_PREFIX}${base_bindir}/k8s-init"
RDEPENDS:${PN}-host = "${PN}"

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
                     "

deltask compile_ptest_base
