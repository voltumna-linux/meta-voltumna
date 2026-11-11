PV = "26.3.0"
SRC_URI[sha256sum] = "91d729aa68bb89e4ec857841300bbe922bcb3e52b1f97566ca83930d3b28343a"

SRC_URI:remove = "file://0001-gallivm-Fix-armhf-build-against-LLVM-22.patch"
SRC_URI:append = " file://45840.patch"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Use the mesa-libclc fork
PACKAGECONFIG[opencl] = "-Dgallium-rusticl=true -Dmesa-clc-bundle-headers=enabled, -Dgallium-rusticl=false, bindgen-cli-native clang mesa-libclc spirv-tools spirv-llvm-translator"

RDEPENDS:libopencl-mesa:remove = "${@bb.utils.contains('PACKAGECONFIG', 'opencl', 'libclc', '', d)}"
RDEPENDS:libopencl-mesa:append = "${@bb.utils.contains('PACKAGECONFIG', 'opencl', ' mesa-libclc', '', d)}"
