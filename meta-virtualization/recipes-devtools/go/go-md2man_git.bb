DESCRIPTION = "A markdown to manpage generator."
HOMEPAGE = "https://github.com/cpuguy83/go-md2man"
SECTION = "devel/go"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://src/${GO_IMPORT}/LICENSE.md;md5=80794f9009df723bbc6fe19234c9f517"

BBCLASSEXTEND = "native"

GO_IMPORT = "github.com/cpuguy83/go-md2man/v2"
GO_INSTALL = "${GO_IMPORT}/..."

SRC_URI = "git://github.com/cpuguy83/go-md2man.git;branch=master;protocol=https;destsuffix=${BPN}-${PV}/src/${GO_IMPORT} \
           gomod://github.com/russross/blackfriday/v2;version=v2.1.0;sha256sum=7852750d58a053ce38b01f2c203208817564f552ebf371b2b630081d7004c6ae \
          "

SRCREV = "061b6c7cbecd6752049221aa15b7a05160796698"
PV = "2.0.7+git"

inherit go-mod

do_compile() {
    cd ${B}/src/${GO_IMPORT}
    ${GO} install ${GOBUILDFLAGS} ./...
}
