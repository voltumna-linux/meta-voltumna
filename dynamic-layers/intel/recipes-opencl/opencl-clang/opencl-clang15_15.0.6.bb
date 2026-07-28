require opencl-clang.inc

SRCREV = "2ce8d3ffbdc10bcbf9f3c42b80ef69babca98522"

BRANCH = "ocl-open-150"

LLVMTBLGENVER = "${LLVM15VERSION}"

EXTRA_OECMAKE += "-DPREFERRED_LLVM_VERSION=${LLVM15VERSION}"

DEPENDS += "clang15 spirv-llvm-translator-llvm15"
DEPENDS:append:class-target = " opencl-clang15-native"
