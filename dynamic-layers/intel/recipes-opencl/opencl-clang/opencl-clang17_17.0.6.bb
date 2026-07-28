require opencl-clang.inc

# ocl-open-170 already contains the upstream fix from PR #464
# ("Request native clang only when cross-compiling"), so the OE backport
# patch reverse-applies. Drop it for this branch.
SRC_URI:remove = " file://0002-Request-native-clang-only-when-cross-compiling-464.patch"

# LLVM 17 keeps clang resource headers under clang/<major>/include while
# compiler-rt installs libs under clang/<major>.<minor>.<patch>/lib. Fix the
# cl_headers header-dir detection so it finds opencl-c.h in the right place.
SRC_URI += "file://0003-cl_headers-locate-OpenCL-headers-via-the-include-sub.patch"

SRCREV = "af0c058f56b5d3f7c703c2ec2aa6ae6cfe541998"

BRANCH = "ocl-open-170"

LLVMTBLGENVER = "${LLVM17VERSION}"

EXTRA_OECMAKE += "-DPREFERRED_LLVM_VERSION=${LLVM17VERSION}"

DEPENDS += "clang17 spirv-llvm-translator-llvm17"
DEPENDS:append:class-target = " opencl-clang17-native"
