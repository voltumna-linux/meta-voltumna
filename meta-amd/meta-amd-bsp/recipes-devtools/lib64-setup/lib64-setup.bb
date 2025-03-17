SUMMARY = "Lib64 setup "
LICENSE = "MIT"

do_install() {
install -d ${D}${base_libdir}/x86_64-linux-gnu
install -m 0644 ${WORKDIR}/recipe-sysroot/usr/lib/libc.so ${D}${base_libdir}/x86_64-linux-gnu
install -d ${D}/lib64
install -m 0755 ${WORKDIR}/recipe-sysroot/lib/ld-linux-x86-64.so.2 ${D}/lib64/
}

FILES:${PN} += "${base_libdir}/x86_64-linux-gnu/libc.so"
FILES:${PN} += "/lib64/ld-linux-x86-64.so.2"

