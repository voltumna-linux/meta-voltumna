BBCLASSEXTEND = "nativesdk"
MACHINE_FEATURES:remove = "qemu-usermode"

# FFTW compiles its SIMD codelets only if they are enabled at configure time:
# the -march from the tune merely vectorizes the generic code. Codelets are
# picked at plan time among those the CPU supports, so a single configuration
# serves every x86-64 machine.
FFTW_SIMD = ""
FFTW_SIMD:x86-64 = "--enable-sse2 --enable-avx --enable-avx2 --enable-avx512"
FFTW_SIMD:class-native = ""

EXTRA_OECONF += "${FFTW_SIMD}"

# Copy of the recipe's do_configure with one change: the long-double library
# has no SIMD codelets and its configure rejects the options above, so they
# are turned back off there (the last occurrence on the command line wins).
do_configure() {
	# configure fftw
	rm -rf ${WORKDIR}/build-fftw
	mkdir -p ${B}
	cd ${B}
	# full (re)configure
	autotools_do_configure
	mv ${B} ${WORKDIR}/build-fftw

	# configure fftwl
	rm -rf ${WORKDIR}/build-fftwl
	mkdir -p ${B}
	cd ${B}
	# configure only
	oe_runconf --enable-long-double --disable-sse2 --disable-avx --disable-avx2 --disable-avx512
	mv ${B} ${WORKDIR}/build-fftwl

	# configure fftwf
	rm -rf ${WORKDIR}/build-fftwf
	mkdir -p ${B}
	cd ${B}
	# configure only
	oe_runconf --enable-single ${FFTW_NEON}
	mv ${B} ${WORKDIR}/build-fftwf
}
