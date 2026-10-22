# Rust 1.95.0 out-of-tree fix, see the patch header for details.

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://0002-Fix-rust-build-failure-with-unstable-options.patch;patchdir=${RUSTSRC} \
	"
