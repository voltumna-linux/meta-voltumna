DESCRIPTION = "The cdi command-line tool is a utility for inspecting and interacting with the CDI (Container Device Interface) cache."
SUMMARY = "The cdi command-line tool."
HOMEPAGE = "https://github.com/cncf-tags/container-device-interface"

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://src/${GO_IMPORT}/LICENSE;md5=86d3f3a95c324c9479bd8986968f4327"

PV = "1.1.0+git"
SRCREV_cdi = "35765bd41b50a86aa3919eb352bc90321e010e68"
SRCREV_FORMAT = "cdi"
SRC_URI = "git://github.com/cncf-tags/container-device-interface.git;protocol=https;name=cdi;branch=main;destsuffix=${GO_SRCURI_DESTSUFFIX} \
          "
SRCREV_FORMAT = "cdi"

GO_IMPORT = "tags.cncf.io/container-device-interface/"

inherit go goarch

# GO_MOD_FETCH_MODE: "vcs" (all git://) or "hybrid" (gomod:// + git://)
GO_MOD_FETCH_MODE ?= "hybrid"

# VCS mode: all modules via git://
include ${@ "go-mod-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}
include ${@ "go-mod-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}

# Hybrid mode: gomod:// for most, git:// for selected
include ${@ "go-mod-hybrid-gomod.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}

do_compile() {
	cd ${S}/src/${GO_IMPORT}
	sed -i -e 's:GO_EXTRAFLAGS:GOBUILDFLAGS:g' Makefile
	oe_runmake
}

do_install() {
        install -d "${D}${bindir}"
        install -m 755 ${S}/src/${GO_IMPORT}/bin/* "${D}${bindir}"
}
