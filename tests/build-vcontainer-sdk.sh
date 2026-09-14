#!/bin/bash
# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# build-vcontainer-sdk.sh
# ===========================================================================
# Build the vcontainer standalone SDK (vdkr + vpdmn + vxn, x86_64 + aarch64)
# in an ISOLATED build dir, so the SDK-based tests (test_vdkr.py, test_vpdmn.py,
# and the vxn dom0 tests) run against a known, reproducible SDK that does NOT
# depend on -- or perturb -- your dev local.conf.
#
# It reuses the CURRENT config's layer stack (copies bblayers.conf) and inherits
# cache/mirror/hashserv settings from your existing build's local.conf (no
# hardcoded paths), but writes its own minimal local.conf assembled from the
# composable vcontainer-sdk-*.conf profiles -- so container package selection is
# deterministic regardless of what your dev local.conf carries.
#
# Usage:
#   tests/build-vcontainer-sdk.sh
#
# Env overrides (all optional):
#   DEV_BUILD        existing build dir to copy layers + cache config from
#                                             (default: $BUILDDIR, else <poky>/build)
#   OE_INIT          path to oe-init-build-env (default: discovered from DEV_BUILD's
#                    bblayers.conf, then bitbake on PATH, then this script's ../..)
#   OECORE_DIR       dir containing oe-init-build-env (alt to OE_INIT)
#   SDK_BUILD_DIR    isolated build dir        (default: sibling of DEV_BUILD)
#   SDK_EXTRACT_DIR  where to extract the SDK  (default: /tmp/vcontainer)
#
# meta-virt need NOT live under the OE-core checkout -- OE-core is found from the
# dev build's layer list, not from where this script sits.
#
# On success it prints the --vdkr-dir path to hand to pytest.

set -eu

here="$(cd "$(dirname "$0")" && pwd)"                       # .../meta-virtualization/tests
# --- existing build to reuse (source of layers + cache config); required ---
DEV_BUILD="${DEV_BUILD:-${BUILDDIR:-}}"
if [ -z "$DEV_BUILD" ] && [ -f "$here/../../build/conf/bblayers.conf" ]; then
    DEV_BUILD="$here/../../build"                       # convenience default (meta-virt under poky)
fi
{ [ -n "$DEV_BUILD" ] && [ -f "$DEV_BUILD/conf/bblayers.conf" ] && [ -f "$DEV_BUILD/conf/local.conf" ]; } || {
    echo "ERROR: set DEV_BUILD to an existing build dir (with conf/{bblayers,local}.conf)," >&2
    echo "       or source your build env first so BUILDDIR is set." >&2
    exit 1
}
DEV_BUILD="$(cd "$DEV_BUILD" && pwd)"

# --- locate oe-init-build-env (OE-core/poky root) ---
# meta-virt is NOT assumed to live under the OE-core checkout. Resolve in order:
#   1. $OE_INIT (path to the script) or $OECORE_DIR (dir containing it)
#   2. the oe-core layer listed in the dev build's bblayers.conf (layout-independent:
#      the core layer sits next to oe-init-build-env)
#   3. bitbake on PATH (a build env is already sourced)
#   4. this script's ../.. (only when meta-virt does live under poky)
resolve_oe_init() {
    if [ -n "${OE_INIT:-}" ] && [ -f "$OE_INIT" ]; then echo "$OE_INIT"; return 0; fi
    if [ -n "${OECORE_DIR:-}" ] && [ -f "$OECORE_DIR/oe-init-build-env" ]; then
        echo "$OECORE_DIR/oe-init-build-env"; return 0
    fi
    local tok bb
    for tok in $(grep -oE '/[^" ]+' "$DEV_BUILD/conf/bblayers.conf" 2>/dev/null); do
        [ -f "$tok/../oe-init-build-env" ] && { echo "$(cd "$tok/.." && pwd)/oe-init-build-env"; return 0; }
    done
    bb="$(command -v bitbake || true)"
    [ -n "$bb" ] && [ -f "$(dirname "$bb")/../../oe-init-build-env" ] && {
        echo "$(cd "$(dirname "$bb")/../.." && pwd)/oe-init-build-env"; return 0; }
    [ -f "$here/../../oe-init-build-env" ] && { echo "$(cd "$here/../.." && pwd)/oe-init-build-env"; return 0; }
    return 1
}
OE_INIT="$(resolve_oe_init)" || {
    echo "ERROR: could not find oe-init-build-env; set OE_INIT=/path/to/oe-init-build-env (or OECORE_DIR)." >&2
    exit 1
}

SDK_BUILD_DIR="${SDK_BUILD_DIR:-$(dirname "$DEV_BUILD")/build-vcontainer-sdk}"
SDK_EXTRACT_DIR="${SDK_EXTRACT_DIR:-/tmp/vcontainer}"

echo "oe-init:     $OE_INIT"
echo "dev build:   $DEV_BUILD (layers + cache config source)"
echo "sdk build:   $SDK_BUILD_DIR (isolated)"
echo "extract to:  $SDK_EXTRACT_DIR"

# oe-init-build-env enters the isolated build dir (does not touch DEV_BUILD).
# It references unset vars (e.g. BBSERVER) and is not `set -u` safe, so relax
# nounset just around the source.
set +u
# shellcheck disable=SC1090
source "$OE_INIT" "$SDK_BUILD_DIR" >/dev/null
set -u

# Reuse the current layer stack verbatim -- "build against the current config".
cp "$DEV_BUILD/conf/bblayers.conf" conf/bblayers.conf

# Minimal, deterministic local.conf:
#   - inherit ONLY cache/mirror/hashserv/parallelism from the dev local.conf
#     (verbatim, so machine-specific paths like DL_DIR/SSTATE_DIR aren't hardcoded
#     here -- they come from whatever that build uses)
#   - the SDK profile stack owns container/arch/multiconfig selection
{
    echo 'MACHINE ?= "qemux86-64"'
    echo 'CONF_VERSION = "2"'
    echo ''
    echo '# systemd init manager -> pulls the usrmerge DISTRO_FEATURE, which modern'
    echo '# systemd REQUIRES; podman/crun/conmon in the vpdmn rootfs depend on systemd.'
    echo '# (meta-virt-host.conf adds the systemd feature but not usrmerge/INIT_MANAGER.)'
    echo 'INIT_MANAGER = "systemd"'
    echo ''
    echo '# Passwordless root so the console-login test can reach a shell (matches a'
    echo '# typical dev local.conf). The vxn dom0 is a throwaway appliance -- the DomU'
    echo '# is the isolation boundary -- and SSH into dom0 is ed25519-key based anyway.'
    echo 'EXTRA_IMAGE_FEATURES ?= "allow-empty-password empty-root-password allow-root-login"'
    echo ''
    echo '# --- inherited from the dev build local.conf (caches/mirrors/hashserv/perf) ---'
    grep -E '^[[:space:]]*(DL_DIR|SSTATE_DIR|SSTATE_MIRRORS|SOURCE_MIRROR_URL|PREMIRRORS|BB_HASHSERVE|BB_HASHSERVE_UPSTREAM|BB_SIGNATURE_HANDLER|BB_NUMBER_THREADS|PARALLEL_MAKE)[[:space:]]*[?:+.]?=' \
        "$DEV_BUILD/conf/local.conf" || true
    echo ''
    echo '# --- vcontainer SDK: everything (vdkr + vpdmn + vxn, x86_64 + aarch64) ---'
    echo 'require conf/distro/include/meta-virt-host.conf'
    echo 'require conf/distro/include/vcontainer-sdk-x86-64.conf'
    echo 'require conf/distro/include/vcontainer-sdk-vdkr-x86-64.conf'
    echo 'require conf/distro/include/vcontainer-sdk-vpdmn-x86-64.conf'
    echo 'require conf/distro/include/vcontainer-sdk-vxn-x86-64.conf'
    echo '# second dom0 blob (podman flavor) so the podman-backend xen tests run;'
    echo '# ships xen-dom0-docker.wic + xen-dom0-podman.wic, boot-xen.sh --flavor selects'
    echo 'require conf/distro/include/vcontainer-sdk-vxn-podman-x86-64.conf'
    echo 'require conf/distro/include/vcontainer-sdk-aarch64.conf'
} > conf/local.conf

echo "=== isolated local.conf ==="
cat conf/local.conf
echo "==========================="

bitbake vcontainer-tarball

installer="$(ls -t tmp/deploy/sdk/vcontainer-standalone.sh 2>/dev/null | head -1)"
[ -n "$installer" ] || { echo "ERROR: no SDK installer produced under $SDK_BUILD_DIR/tmp/deploy/sdk" >&2; exit 1; }

rm -rf "$SDK_EXTRACT_DIR"
"$installer" -d "$SDK_EXTRACT_DIR" -y

echo
echo "SDK built + extracted to: $SDK_EXTRACT_DIR"
echo "Run the SDK-based tests with:"
echo "  pytest tests/test_vdkr.py tests/test_vpdmn.py -v --vdkr-dir $SDK_EXTRACT_DIR"
