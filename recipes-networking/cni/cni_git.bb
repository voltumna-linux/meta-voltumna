HOMEPAGE = "https://github.com/containernetworking/cni"
SUMMARY = "Container Network Interface - networking for Linux containers"
DESCRIPTION = "CNI (Container Network Interface), a Cloud Native Computing \
Foundation project, consists of a specification and libraries for writing \
plugins to configure network interfaces in Linux containers, along with a \
number of supported plugins. CNI concerns itself only with network connectivity \
of containers and removing allocated resources when the container is deleted. \
Because of this focus, CNI has a wide range of support and the specification \
is simple to implement. \
"

SRCREV_cni = "7c270076995b6a35f4774ce94dafcf266d1c6925"
SRCREV_plugins = "6d8f05b82e47b3bf573986146842c08f358270a7"
SRCREV_flannel_plugin = "09e4c7f9bee6abdf56e97f167a85248a7084f7ef"
SRCREV_FORMAT = "cni_plugins"
SRC_URI = "\
	git://github.com/containernetworking/cni.git;branch=main;name=cni;protocol=https;destsuffix=${GO_SRCURI_DESTSUFFIX} \
	"

SRC_URI += "git://github.com/containernetworking/plugins.git;branch=main;destsuffix=${GO_SRCURI_DESTSUFFIX}/src/github.com/containernetworking/plugins;name=plugins;protocol=https"
SRC_URI += "git://github.com/flannel-io/cni-plugin;branch=main;name=flannel_plugin;protocol=https;destsuffix=${GO_SRCURI_DESTSUFFIX}/src/github.com/containernetworking/plugins/plugins/meta/flannel"

include go-mod-git.inc
include go-mod-cache.inc

DEPENDS = " \
    rsync-native \
    "

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://src/import/LICENSE;md5=fa818a259cbed7ce8bc2a22d35a464fc"

GO_IMPORT = "import"

PV = "1.3.0+git"
CNI_VERSION = "v1.3.0"

# go-mod-discovery configuration
# The CNI repo has minimal dependencies. The plugins repo is a separate module
# with its own dependencies, so we need to discover both.
# Primary discovery is for the CNI main repo:
GO_MOD_DISCOVERY_BUILD_TARGET = "./..."
GO_MOD_DISCOVERY_GIT_REPO = "https://github.com/containernetworking/cni.git"
GO_MOD_DISCOVERY_GIT_REF = "${SRCREV_cni}"

# Secondary discovery for the plugins repo - we'll run this manually and merge
# For now, the plugins repo uses its vendor directory

inherit go
inherit goarch
inherit go-mod-discovery

BB_GIT_SHALLOW = "1"

# https://github.com/llvm/llvm-project/issues/53999
TOOLCHAIN = "gcc"

do_compile() {
	mkdir -p ${S}/src/github.com/containernetworking
	ln -sfr ${S}/src/import ${S}/src/github.com/containernetworking/cni

	# Fixes: cannot find package "github.com/containernetworking/plugins/plugins/meta/bandwidth" in any of:
	# we can't clone the plugin source directly to where it belongs because
	# there seems to be an issue in the relocation code from UNPACKDIR to S
	# and our LICENSE file is never found.
	# This symbolic link arranges for the code to be available where go will
	# search during the build
	ln -sfr ${S}/src/import/src/github.com/containernetworking/plugins ${B}/src/github.com/containernetworking

	cd ${B}/src/import

	export GOPATH="${S}/src/import/.gopath:${STAGING_DIR_TARGET}/${prefix}/local/go"
	export GOMODCACHE="${S}/pkg/mod"
	export CGO_ENABLED="1"
	export GOSUMDB="off"
	export GOTOOLCHAIN="local"
	export GOPROXY="off"

	cd ${B}/src/github.com/containernetworking/cni/libcni
	${GO} build -trimpath ${GOBUILDFLAGS}

	cd ${B}/src/github.com/containernetworking/cni/cnitool
	${GO} build -trimpath ${GOBUILDFLAGS}

	cd ${B}/src/import/src/github.com/containernetworking/plugins

	# Build plugins from the plugins repo (excludes flannel which is a separate module)
	# Exclude flannel from this loop - it's from a different repo with a different module path
	PLUGINS="$(ls -d plugins/meta/* | grep -v flannel; ls -d plugins/ipam/*; ls -d plugins/main/* | grep -v windows)"
	mkdir -p ${B}/plugins/bin/
	for p in $PLUGINS; do
	    plugin="$(basename "$p")"
	    echo "building: $p"
	    ${GO} build -trimpath ${GOBUILDFLAGS} -ldflags '-X github.com/containernetworking/plugins/pkg/utils/buildversion.BuildVersion=${CNI_VERSION}' -o ${B}/plugins/bin/$plugin github.com/containernetworking/plugins/$p
	done

	# Build flannel separately - it's from flannel-io/cni-plugin repo with its own module
	# The source was fetched to plugins/meta/flannel but module path is github.com/flannel-io/cni-plugin
	echo "building: flannel (from flannel-io/cni-plugin)"
	cd ${B}/src/import/src/github.com/containernetworking/plugins/plugins/meta/flannel

	# Flannel has its own go.mod/go.sum but its dependencies (containernetworking/cni
	# and containernetworking/plugins) are already available in the plugins vendor directory.
	# Remove go.mod/go.sum so Go treats this as a plain package within the plugins module
	# and uses the vendor directory for dependencies.
	rm -f go.mod go.sum

	# Build from the plugins directory context so -mod=vendor finds deps in plugins/vendor
	cd ${B}/src/import/src/github.com/containernetworking/plugins
	${GO} build -trimpath ${GOBUILDFLAGS} -o ${B}/plugins/bin/flannel ./plugins/meta/flannel
}

do_compile[cleandirs] = "${B}/plugins"

do_install() {
    localbindir="${libexecdir}/cni/"

    install -d ${D}${localbindir}
    install -d ${D}/${sysconfdir}/cni/net.d

    install -m 755 ${S}/src/import/cnitool/cnitool ${D}/${localbindir}
    install -m 755 -D ${B}/plugins/bin/* ${D}/${localbindir}

    # make cnitool more available on the path
    install -d ${D}${bindir}
    ln -sr ${D}/${localbindir}/cnitool ${D}/${bindir}

    # Parts of k8s expect the cni binaries to be available in /opt/cni
    install -d ${D}/opt/cni
    ln -sf ${libexecdir}/cni/ ${D}/opt/cni/bin
}

PACKAGECONFIG ?= "ca-certs"
PACKAGECONFIG[ca-certs] = ",,,ca-certificates"

FILES:${PN} += "${libexecdir}/cni/* /opt/cni/bin"

INSANE_SKIP:${PN} += "ldflags already-stripped"

deltask compile_ptest_base
RRECOMMENDS:${PN} += "iptables iproute2"

# Add CVE_PRODUCT to match the NVD CPE product names
CVE_PRODUCT = "linuxfoundation:container_network_interface linuxfoundation:cni_network_plugins"
