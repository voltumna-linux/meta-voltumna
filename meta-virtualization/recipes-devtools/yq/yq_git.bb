SUMMARY = "a lightweight and portable command-line YAML processor"
HOMEPAGE = "https://github.com/mikefarah/yq"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://src/import/LICENSE;md5=e40a0dcd62f8269b9bff37fe9aa7dcc2"

SRCREV_yq = "0f4fb8d35ec1a939d78dd6862f494d19ec589f19"
SRCREV_FORMAT = "yq"

SRC_URI = "git://github.com/mikefarah/yq.git;name=yq;branch=master;protocol=https;destsuffix=${GO_SRCURI_DESTSUFFIX} \
           file://run-ptest \
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

PV = "4.52.5+git"

GO_IMPORT = "import"

# go-mod-discovery configuration
GO_MOD_DISCOVERY_BUILD_TARGET = "./..."
GO_MOD_DISCOVERY_GIT_REPO = "https://github.com/mikefarah/yq.git"
GO_MOD_DISCOVERY_GIT_REF = "${SRCREV_yq}"

inherit go goarch ptest
inherit go-mod-discovery

# GO's internal linker doesn't support PIE for linux 32 bits target,
# so -buildmode=pie requires external (cgo) linking on ARM and x86.
GOBUILDFLAGS:remove = "-buildmode=pie"

do_compile() {
    cd ${S}/src/import

    export GOPATH="${S}/src/import/.gopath:${STAGING_DIR_TARGET}/${prefix}/local/go"
    export CGO_ENABLED="0"

    ${GO} build -trimpath ${GOBUILDFLAGS} -o ${B}/yq .
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/yq ${D}${bindir}/yq
}

do_install_ptest() {
    install -d ${D}${PTEST_PATH}/tests
    cp -r ${S}/src/import/scripts/* ${D}${PTEST_PATH}/tests
    cp -r ${S}/src/import/acceptance_tests/* ${D}${PTEST_PATH}/tests
    cp -r ${S}/src/import/examples ${D}${PTEST_PATH}/tests
}

RDEPENDS:${PN}-ptest += "bash"
RDEPENDS:${PN}-dev += "bash"

BBCLASSEXTEND = "native"
