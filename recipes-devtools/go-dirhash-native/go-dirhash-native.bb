SUMMARY = "Go dirhash helper for offline Go module checksum generation"
HOMEPAGE = "https://go.googlesource.com/mod"

LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=7998cb338f82d15c0eff93b7004d272a"

SRC_URI = "git://go.googlesource.com/mod;protocol=https;nobranch=1;rev=f8a9fe217cff893cb67f4acad96a0021c13ee6e7;destsuffix=git/mod \
           file://dirhash-helper.go \
           file://LICENSE"

S = "${UNPACKDIR}/git/mod"

PV = "1.0"

DEPENDS = "go-native"

inherit go native

do_compile() {
    dirhash_gopath="${WORKDIR}/dirhash-gopath"
    dirhash_gocache="${WORKDIR}/dirhash-gocache"
    dirhash_gomodcache="${WORKDIR}/dirhash-gomodcache"

    install -d "${dirhash_gopath}/src/dirhash-helper"
    install -d "${dirhash_gopath}/src/golang.org/x"

    cp "${UNPACKDIR}/dirhash-helper.go" "${dirhash_gopath}/src/dirhash-helper/main.go"
    cp -a "${S}" "${dirhash_gopath}/src/golang.org/x/mod"

    bbnote "Building dirhash helper"
    (
        cd "${dirhash_gopath}/src/dirhash-helper" && \
        GOPATH="${dirhash_gopath}" \
        GOCACHE="${dirhash_gocache}" \
        GOMODCACHE="${dirhash_gomodcache}" \
        GO111MODULE="off" \
        ${GO} build -o dirhash .
    )
}

do_install() {
    install -d "${D}${bindir}"
    dirhash_gopath="${WORKDIR}/dirhash-gopath"
    install -m 0755 "${dirhash_gopath}/src/dirhash-helper/dirhash" "${D}${bindir}/dirhash"

    install -d "${D}${datadir}/licenses/${PN}"
    install -m 0644 "${UNPACKDIR}/LICENSE" "${D}${datadir}/licenses/${PN}/LICENSE"
}
