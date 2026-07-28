LICENSE = "NCSA"
LIC_FILES_CHKSUM = "file://LICENSE.TXT;md5=47e311aa9caedd1b3abf098bd7814d1d"

BRANCH = "llvm_release_150"
SRC_URI = "git://github.com/KhronosGroup/SPIRV-LLVM-Translator;protocol=https;branch=${BRANCH}"

PV = "15.0.20"
SRCREV = "fbf70cecedc348de194f25df902e290bad94cd4b"

DEPENDS = "spirv-headers spirv-tools spirv-tools-native clang15"

inherit cmake pkgconfig python3native

# Specify any options you want to pass to cmake using EXTRA_OECMAKE:
# for CMAKE_SHARED_LIBS=OFF see https://github.com/KhronosGroup/SPIRV-LLVM-Translator/issues/1868
EXTRA_OECMAKE = "\
        -DBASE_LLVM_VERSION=${LLVM15VERSION} \
        -DBUILD_SHARED_LIBS=ON \
        -DLLVM_LINK_LLVM_DYLIB=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_SKIP_RPATH=ON \
        -DLLVM_EXTERNAL_LIT=lit \
        -DLLVM_INCLUDE_TESTS=ON \
        -Wno-dev \
        -DCCACHE_ALLOWED=FALSE \
"

DEBIAN_NOAUTONAME:${PN} = "1"
DEBIAN_NOAUTONAME:${PN}-bin = "1"
DEBIAN_NOAUTONAME:${PN}-dbg = "1"
DEBIAN_NOAUTONAME:${PN}-dev = "1"
DEBIAN_NOAUTONAME:${PN}-src = "1"

PACKAGES =+ "${PN}-bin"
FILES:${PN}-bin = "${bindir}/*"

BBCLASSEXTEND = "native nativesdk"

EXCLUDE_FROM_WORLD = "1"
