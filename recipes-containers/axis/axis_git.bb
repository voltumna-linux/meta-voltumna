SUMMARY = "AXIS: Agent eXecution Isolation Substrate (CLI)"
DESCRIPTION = "CLI for sandboxed AI agent execution. `axis run --policy vxn -- <tool>` \
launches an agent inside an isolated Xen DomU via the vxn backend. Cross-compiled \
here so a dom0 that ships it runs config-b (axis-in-dom0) with zero host setup and \
no glibc/loader mismatch."
HOMEPAGE = "https://github.com/ROCm/axis"
BUGTRACKER = "https://github.com/ROCm/axis/issues"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=22a86b72065b4172ceb06680d8d6e1a4"

# Fetch axis from upstream ROCm/axis at a fixed base commit and carry the vxn
# backend as patches -- the vxn series is not upstream yet, and a meta-virt
# recipe cannot track a personal fork. SRCREV is the fork point of the
# vxn-backend branch on ROCm/axis main, so the patches apply cleanly. When the
# series merges upstream, drop the file:// patches and bump SRCREV.
SRC_URI = "git://github.com/ROCm/axis.git;protocol=https;branch=main \
    file://0001-sandbox-add-vxn-RuntimeProvider-Xen-DomU-isolation-b.patch \
    file://0002-sandbox-vxn-backend-passes-container-argv-opaquely.patch \
    file://0003-sandbox-vxn-backend-forwards-SandboxConfig.env-to-th.patch \
    file://0004-vxn-forward-explicitly-named-host-env-vars-into-the-.patch \
    file://0005-vxn-derive-the-DomU-image-from-the-command-name.patch \
    file://0006-vxn-add-it-for-interactive-terminals.patch \
    file://0007-vxn-add-a-built-in-vxn-policy-so-axis-run-policy-vxn.patch \
    file://0008-docs-add-vxn-backend-guide.patch \
    file://0009-vxn-carry-the-process-limit-policy-into-the-DomU.patch \
    file://0010-vxn-carry-the-filesystem-policy-into-the-DomU.patch \
    "
SRCREV = "fe981ef99a2c4c73499b003600fa8d599617ab85"

PV = "0.3.5+git"

inherit cargo cargo-update-recipe-crates

require ${BPN}-crates.inc

# Build only the CLI (bin name: axis). The workspace also builds axis-daemon
# (axisd) and helpers unused by the vxn integration -- `axis run` falls back to
# standalone mode when no daemon is present, so the CLI alone is sufficient.
# gui/linux is already excluded from the workspace.
CARGO_BUILD_FLAGS += "-p axis-cli"

# TLS is rustls with the `ring` crypto provider (per Cargo.lock -- not aws-lc-rs),
# which ships prebuilt x86_64 asm and cross-compiles cleanly with just the cargo
# toolchain. If a build ever resolves ring on a target without prebuilt asm, it
# regenerates via perl -> add `DEPENDS += "perl-native"` then.

# axis uses edition 2024 -> needs Rust >= 1.85 (poky master satisfies this).
