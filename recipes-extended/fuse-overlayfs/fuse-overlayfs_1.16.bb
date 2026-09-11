SUMMARY = "FUSE implementation of overlayfs."
DESCRIPTION = "An implementation of overlay+shiftfs in FUSE for rootless \
containers."

LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://COPYING;md5=b234ee4d69f5fce4486a80fdaf4a4263"

SRCREV = "72c86e60ebc9424189725e47e8649472e7caa45a"
SRC_URI = "git://github.com/containers/fuse-overlayfs.git;nobranch=1;protocol=https"

# Upstream rewrote fuse-overlayfs from C to Rust in commits 7126904
# (the rewrite) and 528270c (C implementation removal), on the v1.16-tip
# line. The recipe now drives the cargo build instead of autotools;
# Cargo.toml at this SRCREV self-identifies as version 2.0.0 but no
# tag has been cut yet, so the filename PV stays at 1.16 per the
# tip-past-tag convention (cowsql, raft).
inherit cargo cargo-update-recipe-crates

# Cargo.toml declares [profile.release] strip = true, which causes cargo
# to strip the binary before bitbake's debug-split machinery runs and
# triggers an [already-stripped] QA failure. Override via --config so we
# don't need to carry a patch against an upstream choice.
CARGO_BUILD_FLAGS += "--config profile.release.strip=false"

require ${BPN}-crates.inc
