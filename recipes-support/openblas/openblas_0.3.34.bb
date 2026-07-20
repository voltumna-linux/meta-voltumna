DESCRIPTION = "OpenBLAS is an optimized BLAS library based on GotoBLAS2 1.13 BSD version."
HOMEPAGE = "http://www.openblas.net/"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=5adf4792c949a00013ce25d476a2abc0"

inherit siteinfo

DEPENDS += "libgfortran"
RDEPENDS:${PN} += "libgomp"

SRCREV = "e0166008be8e466242aa76b2ff75ce3f0fbf574a"
SRC_URI = "git://github.com/xianyi/OpenBLAS.git;protocol=https;branch=release-0.3.0"

# Full BLAS plus the bundled netlib LAPACK/LAPACKE inside libopenblas, LP64
# interface. NUM_THREADS is only the runtime thread cap (256 = EPYC 9755 hw
# threads); left unset it would default to the build host core count.
EXTRA_OEMAKE += " \
	FORCE_${OPENBLAS_TARGET}="1" \
	TARGET=${OPENBLAS_TARGET} \
	BINARY=${SITEINFO_BITS} \
	NO_LAPACK="0" \
	NO_LAPACKE="0" \
	BUILD_LAPACK_DEPRECATED="1" \
	INTERFACE64="0" \
	NUM_THREADS="256" \
	NO_AFFINITY="1" \
	USE_OPENMP="1" \
	HOSTCC="${BUILD_CC}" \
	CC="${CC}" \
	FC="${FC}" \
	PREFIX=${exec_prefix} \
	CROSS_SUFFIX=${HOST_PREFIX} \
	DESTDIR=${D} \
	"

# Separate goals: with parallel make, goals given on one command line are
# pursued concurrently.
do_compile() {
	# The cross toolchain provides no omp_lib.mod (libgomp's Fortran module
	# is built by neither gcc-runtime nor libgfortran), so the bundled
	# LAPACK cannot be compiled with -fopenmp: strip it the same way
	# upstream does on Windows. Only the two-stage eigensolvers lose their
	# internal threading; parallelism stays in the OpenMP BLAS kernels.
	lapack_noomp='LAPACK_FFLAGS=$(filter-out -fopenmp -mp -openmp -xopenmp=parallel,$(FFLAGS))'
	oe_runmake libs
	oe_runmake netlib "$lapack_noomp"
	oe_runmake shared "$lapack_noomp"
}

do_install() {
	oe_runmake install
	rmdir ${D}${bindir}
	# libopenblas replaces netlib as the system BLAS/LAPACK/LAPACKE provider
	for l in blas lapack lapacke; do
		ln -sf libopenblas.so.0 ${D}${libdir}/lib${l}.so.3
		ln -sf libopenblas.so ${D}${libdir}/lib${l}.so
	done
}

FILES:${PN}     = "${libdir}/*"
FILES:${PN}-dev = "${includedir} ${libdir}/lib${PN}.so ${libdir}/pkgconfig ${libdir}/cmake \
                   ${libdir}/libblas.so ${libdir}/liblapack.so ${libdir}/liblapacke.so"

# Fortran is not enabled with clang
TOOLCHAIN = "gcc"

BBCLASSEXTEND = "nativesdk"
