# libva needs mesa which may be built with a different LLVM version
# that was used to build intel-graphics-compiler.
# This avoids pulling in the conflicting clang and clangNN versions
# into the same build.
DEPENDS:remove = "libva"
DEPENDS:append = " libva-initial"
