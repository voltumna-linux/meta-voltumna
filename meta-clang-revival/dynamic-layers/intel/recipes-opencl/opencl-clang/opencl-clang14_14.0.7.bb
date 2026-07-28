require opencl-clang.inc

SRCREV = "6de07bb3181293631ba8dcb53d5a760cb091c166"

BRANCH = "ocl-open-140"

LLVMTBLGENVER = "${LLVM14VERSION}"

EXTRA_OECMAKE += "-DPREFERRED_LLVM_VERSION=${LLVM14VERSION}"

DEPENDS += "clang14 spirv-llvm-translator-llvm14"
DEPENDS:append:class-target = " opencl-clang14-native"
