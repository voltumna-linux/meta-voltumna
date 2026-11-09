# libva needs mesa which can be build with a different LLVM version
# that was used to build intel-graphics-compiler.
# This avoids pulling in the conflicting clang and clangNN versions.
DEPENDS:remove = "libva"
DEPENDS:append = " libva-initial"
