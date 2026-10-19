PV = "26.2.5"
SRC_URI[sha256sum] = "794b3d1729075dae7ebd47c7283b7ca0cdb5dec668f7f11cc0a5d82f6138a0a5"

SRC_URI:remove = "file://0001-gallivm-Fix-armhf-build-against-LLVM-22.patch"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Use the mesa-libclc fork
PACKAGECONFIG[opencl] = "-Dgallium-rusticl=true -Dmesa-clc-bundle-headers=enabled, -Dgallium-rusticl=false, bindgen-cli-native clang mesa-libclc spirv-tools spirv-llvm-translator"

RDEPENDS:libopencl-mesa:remove = "${@bb.utils.contains('PACKAGECONFIG', 'opencl', 'libclc', '', d)}"
RDEPENDS:libopencl-mesa:append = "${@bb.utils.contains('PACKAGECONFIG', 'opencl', ' mesa-libclc', '', d)}"
