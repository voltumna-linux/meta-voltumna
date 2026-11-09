DEPENDS:remove = "clang spirv-llvm-translator"
DEPENDS:append = " clang15 spirv-llvm-translator-llvm15"

EXTRA_OECMAKE:remove = "-DPREFERRED_LLVM_VERSION=${LLVMVERSION}"
EXTRA_OECMAKE:append = " -DPREFERRED_LLVM_VERSION=${LLVM15VERSION}"
