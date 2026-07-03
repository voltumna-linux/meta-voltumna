# Link NumPy against OpenBLAS (BLAS + LAPACK). Target only: openblas has no
# native variant and native/nativesdk numpy builds do not need BLAS.
DEPENDS:append:class-target = " openblas"
EXTRA_OEMESON:append:class-target = " -Dblas=openblas -Dlapack=openblas -Dallow-noblas=false"
