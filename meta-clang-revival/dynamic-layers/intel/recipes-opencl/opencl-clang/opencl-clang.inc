SUMMARY = "Common clang is a thin wrapper library around clang"
DESCRIPTION = "Common clang has OpenCL-oriented API and is capable \
 to compile OpenCL C kernels to SPIR-V modules."

LICENSE = "NCSA"
LIC_FILES_CHKSUM = "file://LICENSE;md5=e8a15bf1416762a09ece07e44c79118c"

SRC_URI = "git://github.com/intel/opencl-clang.git;branch=${BRANCH};protocol=https \
           file://0002-Request-native-clang-only-when-cross-compiling-464.patch \
           file://0001-cl_headers-CMakeLists.txt-use-clang-from-native-sysr.patch \
           "

inherit cmake

COMPATIBLE_HOST = '(x86_64).*-linux'
COMPATIBLE_HOST:libc-musl = "null"

LLVMTBLGENVER ?= ""

CXXFLAGS += "-I${STAGING_INCDIR}/LLVMSPIRVLib"

EXTRA_OECMAKE += "\
                  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
                  -DLLVM_TABLEGEN_EXE=${STAGING_BINDIR_NATIVE}/llvm-tblgen${LLVMTBLGENVER} \
                  -DCMAKE_SKIP_RPATH=TRUE \
                  "

do_install:append:class-native() {
        install -d ${D}${bindir}
        install -m 0755 ${B}/bin/linux_resource_linker ${D}${bindir}/
}

INSANE_SKIP:${PN} = "buildpaths"

DEBIAN_NOAUTONAME:${PN} = "1"
DEBIAN_NOAUTONAME:${PN}-dbg = "1"
DEBIAN_NOAUTONAME:${PN}-dev = "1"
DEBIAN_NOAUTONAME:${PN}-src = "1"

BBCLASSEXTEND = "native nativesdk"
