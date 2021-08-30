DESCRIPTION = "Provides the Non-Volatile Memory (NVM) Update Utility for Intel Ethernet Network Adapter 700 Series."
HOMEPAGE = "https://www.intel.com/content/www/us/en/download/18190/non-volatile-memory-nvm-update-utility-for-intel-ethernet-network-adapter-700-series.html"
LICENSE = "CLOSED"

SRC_URI = "https://downloadmirror.intel.com/682037/700Series_NVMUpdatePackage_v8_50.zip"
SRC_URI[sha256sum] = "99e65b036289303eabf0e5fcf2fb0f3f8c8ffa2660b261b610b6c7ea51c07f85"
COMPATIBLE_HOST = "x86_64.*-linux"

PACKAGES = "${BPN}"

INSANE_SKIP_${PN} = "already-stripped"

do_extract_data() {
	tar zxf ${WORKDIR}/*_Linux.tar.gz -C "${S}"
}

python do_unpack_append() {
    bb.build.exec_func('do_extract_data', d)
}

do_install() {
	install -m 0755 -d ${D}${datadir}/${BPN}
	install -m 0644 ${S}/*/*/* ${D}${datadir}/${BPN}
	chmod 755 ${D}${datadir}/${BPN}/nvmupdate64e
}
