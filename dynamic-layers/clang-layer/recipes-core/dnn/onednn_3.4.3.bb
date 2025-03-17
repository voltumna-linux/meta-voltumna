HOMEPAGE = "https://www.oneapi.com"
SUMMARY  = "Deep Neural Network Library"
DESCRIPTION = "This software is a user mode library that accelerates\
deep-learning applications and frameworks on Intel architecture."
LICENSE  = "Apache-2.0 & BSD-3-Clause & BSL-1.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3b64000f6e7d52516017622a37a94ce9 \
                    file://tests/gtests/gtest/LICENSE;md5=cbbd27594afd089daa160d3a16dd515a \
                    file://src/cpu/x64/xbyak/COPYRIGHT;md5=3b9bf048d063d54cdb28964db558bcc7 \
                    file://src/common/ittnotify/LICENSE.BSD;md5=e671ff178b24a95a382ba670503c66fb \
                    "
SECTION = "lib"

inherit pkgconfig cmake ptest

DNN_BRANCH = "rls-v${@'.'.join(d.getVar('PV').split('.')[0:2])}"

S = "${WORKDIR}/git"
SRCREV = "8a037f772264108cca48f5244b4539ad5359ff7c"
SRC_URI = "git://github.com/oneapi-src/oneDNN.git;branch=${DNN_BRANCH};protocol=https \
           file://run-ptest \
           "

UPSTREAM_CHECK_GITTAGREGEX = "^v(?P<pver>(\d+(\.\d+)+))$"

CVE_PRODUCT = "intel:math_kernel_library"

COMPATIBLE_HOST = '(x86_64).*-linux'
COMPATIBLE_HOST:libc-musl = 'null'

EXTRA_OECMAKE += " \
                   -DDNNL_LIBRARY_TYPE=SHARED \
                   -DDNNL_BUILD_EXAMPLES=ON \
                   -DDNNL_BUILD_TESTS=ON \
                   -DDNNL_CPU_RUNTIME=OMP \
                   -DDNNL_ARCH_OPT_FLAGS="" \
                   -DCMAKE_SKIP_RPATH=ON \
                   -DONEDNN_BUILD_GRAPH=OFF \
                   "

PACKAGECONFIG ??= "gpu"
PACKAGECONFIG[gpu] = "-DDNNL_GPU_RUNTIME=OCL, , opencl-headers virtual/opencl-icd, intel-compute-runtime"

do_install:append () {
    install -d ${D}${bindir}/mkl-dnn/tests/benchdnn/inputs
    install -m 0755 ${B}/tests/benchdnn/benchdnn ${D}${bindir}/mkl-dnn/tests/benchdnn
    cp -r ${B}/tests/benchdnn/inputs/* ${D}${bindir}/mkl-dnn/tests/benchdnn/inputs
}

do_install_ptest () {
    install -d ${D}${PTEST_PATH}/tests
    install -m 0755 ${B}/tests/api-c ${D}${PTEST_PATH}/tests
    install -m 0755 ${B}/tests/test_c_symbols-c ${D}${PTEST_PATH}/tests
}

PACKAGES =+ "${PN}-test"

FILES:${PN}-test = "${bindir}/mkl-dnn/*"
