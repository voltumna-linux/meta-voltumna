FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
        file://0001-Restore-PowerPC-SPE-e500-support-for-glibc-2.43.patch \
        file://0002-powerpc-Add-__feclearexcept-and-__fetestexcept-inter.patch \
	"

SYSROOT_PREPROCESS_FUNCS:append:ppce500v2 = " create_ld_compat_symlink"
create_ld_compat_symlink() {
    install -d ${SYSROOT_DESTDIR}/lib
    ln -sfrn ${SYSROOT_DESTDIR}/usr/lib/ld.so.1 ${SYSROOT_DESTDIR}/lib/ld.so.1
}
