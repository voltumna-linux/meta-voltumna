SUMMARY = "Detect if we are running in a virtual machine"
HOMEPAGE = "https://people.redhat.com/~rjones/virt-what/"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=b234ee4d69f5fce4486a80fdaf4a4263"

SRC_URI = "https://people.redhat.com/~rjones/virt-what/files/${BP}.tar.gz"
SRC_URI[sha256sum] = "d4d9bd9d4ae59095597443fac663495315c7eb4330b872aa5f062df38ac69bf1"

DEPENDS = "perl-native"

inherit autotools
