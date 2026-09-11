SUMMARY = "crosvm is a secure, lightweight, and performant Virtual Machine Monitor (VMM) written in Rust."

DESCRIPTION = "\
crosvm is a Rust-based virtual machine monitor (VMM) originally developed \
for ChromeOS. It uses KVM acceleration and process-level isolation to run guest VMs \
with sandboxed device emulation.\
"

HOMEPAGE = "https://github.com/google/crosvm"

LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=4777ca8ce9fd4f089e88af15fce91131"

inherit cargo pkgconfig cargo-update-recipe-crates features_check

SRC_URI = " \
    git://github.com/google/crosvm.git;branch=main;protocol=https;name=crosvm \
    git://github.com/google/minijail.git;branch=main;protocol=https;name=minijail;destsuffix=${BB_GIT_DEFAULT_DESTSUFFIX}/third_party/minijail \
"

SRCREV_crosvm = "4156aed946818f1e86803d645b5d57229475d9a4"
SRCREV_minijail = "7845d89927a82dbdcdee6276837cd0978f69ba19"

SRCREV_FORMAT = "crosvm_minijail"

# crosvm does not publish upstream release tags.
# PV = "0.1.0" is an intentionally cosmetic/local version for layer
# consistency, not an upstream project release.
PV = "0.1.0+git"

# TODO: Break this down into pkgconfig flags mapped to
# rust cargo feature flags.
DEPENDS += "libcap wayland wayland-native protobuf-native wayland-protocols clang-native"

REQUIRED_DISTRO_FEATURES = "kvm"

COMPATIBLE_HOST = "(aarch64|x86_64).*-linux.*"

# minijail-sys's build.rs uses the bindgen crate (in-process libclang) to
# generate Rust FFI bindings for libminijail.h. Point bindgen at the
# clang-native libclang and pass the toolchain and target options so that
# cross-compiled header parsing resolves correctly.
export LIBCLANG_PATH = "${STAGING_LIBDIR_NATIVE}"
export BINDGEN_EXTRA_CLANG_ARGS = "--sysroot=${STAGING_DIR_HOST}"

# crosvm's own Cargo.toml already supplies [patch.crates-io] minijail =
#   { path = "third_party/minijail/rust/minijail" }
# pointing at the rust/minijail subdirectory, where minijail's Cargo.toml
# actually lives. cargo_common_do_patch_paths() would inject a competing
# [patch."<minijail git URL>"] minijail = { path = "<unpackdir>/git/third_party/minijail" }
# pointing at the minijail repo root, where there is no Cargo.toml — Cargo
# eagerly validates patch entries and errors out before it would even reach
# the "unused patch" path. Disable the auto-injection; crosvm's upstream
# [patch] table is the authoritative one.
python () {
   pf = (d.getVarFlag("do_configure", "postfuncs") or "").split()
   pf = [f for f in pf if f != "cargo_common_do_patch_paths"]
   d.setVarFlag("do_configure", "postfuncs", " ".join(pf))
}

require crosvm-crates.inc
