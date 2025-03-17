# Hackish because this should be handled in the actual module
# classes (module module-base), a kernel with configurations
# such as CONFIG_MODULE_SIG requires openssl native bits
# to build properly.
DEPENDS += "openssl-native"
do_make_scripts() {
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS 
    make HOSTCC="${BUILD_CC} ${BUILD_CFLAGS} ${BUILD_LDFLAGS}" HOSTCPP="${BUILD_CPP}" \
        CC="${KERNEL_CC}" LD="${KERNEL_LD}" AR="${KERNEL_AR}" \
	-C ${STAGING_KERNEL_DIR} O=${STAGING_KERNEL_BUILDDIR} scripts
}
