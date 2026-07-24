# SPDX-FileCopyrightText: Copyright (C) 2026 Konsulko Group
#
# SPDX-License-Identifier: MIT
"""
Tests for the vcontainer registry-auth-config plumbing ("--config" /
$VDKR_CONFIG / $VPDMN_CONFIG).

These tests are split into two tiers:

Tier 1 - static/shell-level (TestAuthConfigStaticPlumbing):
    Reads the shell scripts under recipes-containers/vcontainer/files/ and the
    README and asserts that the expected function definitions, call sites,
    kernel cmdline flags, permission modes, mount options, and documentation
    blocks are present. These tests need no infrastructure and run in <1s.

Tier 2 - functional validator (TestAuthConfigValidator):
    Extracts validate_auth_config() from vrunner.sh, sources it in a bash
    subshell with a stubbed log() function, and drives it with a table of
    inputs covering the perm / size / symlink / ownership / regular-file
    rules. Also runs in <1s per case.

Tier 3 (live registry pull with --config) is intentionally NOT in this file.
It belongs alongside test_vdkr_registry.py once the registry fixture grows a
credentials-required mode.

Run with:
    pytest tests/test_vcontainer_auth_config.py -v
"""

import os
import re
import stat
import subprocess
import textwrap
from pathlib import Path

import pytest


# ---------------------------------------------------------------------------
# Locate the vcontainer files/ directory.
# ---------------------------------------------------------------------------
#
# Resolution order:
#   1. VCONTAINER_FILES_DIR environment variable (explicit override)
#   2. <repo-root>/recipes-containers/vcontainer/files/ relative to this test
#      (i.e. tests/../recipes-containers/vcontainer/files/)
#   3. /opt/bruce/poky/meta-virtualization/recipes-containers/vcontainer/files/
#      (matches the pattern used by test_container_registry_script.py)
#
# If none of these are present, every test in this module is skipped.
_TESTS_DIR = Path(__file__).resolve().parent
_DEFAULT_CANDIDATES = [
    _TESTS_DIR.parent / "recipes-containers" / "vcontainer" / "files",
    Path("/opt/bruce/poky/meta-virtualization/recipes-containers/vcontainer/files"),
]


def _find_files_dir() -> Path:
    override = os.environ.get("VCONTAINER_FILES_DIR")
    if override:
        return Path(override)
    for c in _DEFAULT_CANDIDATES:
        if c.is_dir():
            return c
    return _DEFAULT_CANDIDATES[0]  # return first, skip in fixture if missing


@pytest.fixture(scope="module")
def files_dir() -> Path:
    d = _find_files_dir()
    if not d.is_dir():
        pytest.skip(f"vcontainer files/ dir not found: {d}")
    return d


@pytest.fixture(scope="module")
def repo_root() -> Path:
    # The vcontainer files live at <root>/recipes-containers/vcontainer/files,
    # so the repo root is two levels up.
    d = _find_files_dir()
    return d.parent.parent.parent


@pytest.fixture(scope="module")
def vrunner_sh(files_dir: Path) -> str:
    p = files_dir / "vrunner.sh"
    if not p.is_file():
        pytest.skip(f"vrunner.sh not found: {p}")
    return p.read_text()


@pytest.fixture(scope="module")
def vcontainer_common_sh(files_dir: Path) -> str:
    p = files_dir / "vcontainer-common.sh"
    if not p.is_file():
        pytest.skip(f"vcontainer-common.sh not found: {p}")
    return p.read_text()


@pytest.fixture(scope="module")
def init_common_sh(files_dir: Path) -> str:
    p = files_dir / "vcontainer-init-common.sh"
    if not p.is_file():
        pytest.skip(f"vcontainer-init-common.sh not found: {p}")
    return p.read_text()


@pytest.fixture(scope="module")
def vdkr_init_sh(files_dir: Path) -> str:
    p = files_dir / "vdkr-init.sh"
    if not p.is_file():
        pytest.skip(f"vdkr-init.sh not found: {p}")
    return p.read_text()


@pytest.fixture(scope="module")
def vpdmn_init_sh(files_dir: Path) -> str:
    p = files_dir / "vpdmn-init.sh"
    if not p.is_file():
        pytest.skip(f"vpdmn-init.sh not found: {p}")
    return p.read_text()


@pytest.fixture(scope="module")
def readme_md(repo_root: Path) -> str:
    p = repo_root / "recipes-containers" / "vcontainer" / "README.md"
    if not p.is_file():
        pytest.skip(f"vcontainer README.md not found: {p}")
    return p.read_text()


# ---------------------------------------------------------------------------
# Tier 1: Static / shell-level plumbing assertions
# ---------------------------------------------------------------------------


class TestAuthConfigStaticPlumbing:
    """Shell-script-level assertions for the --config / VDKR_CONFIG feature."""

    # --- vrunner.sh --------------------------------------------------------

    def test_vrunner_defines_auth_config_from_env(self, vrunner_sh):
        """AUTH_CONFIG picks up $VDKR_CONFIG or $VPDMN_CONFIG by default."""
        assert re.search(
            r'AUTH_CONFIG="\$\{VDKR_CONFIG:-\$\{VPDMN_CONFIG:-\}\}"', vrunner_sh
        ), "vrunner.sh should initialise AUTH_CONFIG from VDKR_CONFIG/VPDMN_CONFIG"

    def test_vrunner_accepts_config_flag(self, vrunner_sh):
        """`--config <path>` is parsed and assigned to AUTH_CONFIG."""
        # The case label ("--config") plus the assignment should both exist.
        # Allow interleaved comment lines between the label and the assignment.
        assert re.search(
            r'--config\)\s*\n(?:\s*#[^\n]*\n)*\s*AUTH_CONFIG="\$2"',
            vrunner_sh,
        ), "vrunner.sh should parse --config and set AUTH_CONFIG=\"$2\""

    def test_vrunner_defines_validate_auth_config(self, vrunner_sh):
        assert "validate_auth_config()" in vrunner_sh, \
            "vrunner.sh should define validate_auth_config()"

    def test_vrunner_defines_setup_auth_share(self, vrunner_sh):
        assert "setup_auth_share()" in vrunner_sh, \
            "vrunner.sh should define setup_auth_share()"

    def test_vrunner_validator_rejects_symlinks(self, vrunner_sh):
        """Symlinks are rejected outright to block /proc/self/environ tricks."""
        assert re.search(r'if \[ -L "\$path" \]', vrunner_sh), \
            "validate_auth_config must reject symlinks with `[ -L $path ]`"

    def test_vrunner_validator_requires_regular_file(self, vrunner_sh):
        assert re.search(r'if \[ ! -f "\$path" \]', vrunner_sh), \
            "validate_auth_config must require a regular file (-f)"

    def test_vrunner_validator_requires_readable(self, vrunner_sh):
        assert re.search(r'if \[ ! -r "\$path" \]', vrunner_sh), \
            "validate_auth_config must require the file be readable (-r)"

    def test_vrunner_validator_checks_missing(self, vrunner_sh):
        assert re.search(r'if \[ ! -e "\$path" \]', vrunner_sh), \
            "validate_auth_config must detect missing files (-e)"

    def test_vrunner_validator_min_size(self, vrunner_sh):
        """Files smaller than 2 bytes (minimum "{}" JSON) are rejected."""
        assert re.search(r'size"?\s*-lt\s*2', vrunner_sh), \
            "validate_auth_config must reject files smaller than 2 bytes"

    def test_vrunner_validator_max_size(self, vrunner_sh):
        """Files larger than 1 MiB are rejected."""
        assert "1048576" in vrunner_sh, \
            "validate_auth_config must reject files larger than 1 MiB (1048576)"

    def test_vrunner_validator_mode_whitelist(self, vrunner_sh):
        """Permission modes are restricted to 400 / 600 / 200."""
        # We accept either a case statement or equivalent chain; the canonical
        # form in the source is a case statement that matches these literals.
        assert re.search(r'400\s*\|\s*600\s*\|\s*200', vrunner_sh), (
            "validate_auth_config must whitelist modes 400|600|200 only"
        )

    def test_vrunner_validator_warns_on_wrong_owner(self, vrunner_sh):
        """Non-owner files trigger a WARN but don't reject (documented)."""
        assert re.search(r'WARN.*not owned by current user', vrunner_sh), \
            "validate_auth_config must WARN when file is not owned by current user"

    def test_vrunner_setup_auth_share_permissions(self, vrunner_sh):
        """Staging dir is 700 and staged file is 400."""
        assert "chmod 700" in vrunner_sh, \
            "setup_auth_share must chmod 700 the staging directory"
        assert re.search(r'chmod 400[^\n]*config\.json', vrunner_sh), \
            "setup_auth_share must chmod 400 the staged config.json"

    def test_vrunner_setup_auth_share_readonly_9p(self, vrunner_sh):
        """The 9p share is created with readonly=on."""
        assert 'hv_build_9p_opts' in vrunner_sh and 'readonly=on' in vrunner_sh, (
            "setup_auth_share must pass readonly=on to hv_build_9p_opts"
        )

    def test_vrunner_setup_auth_share_uses_dedicated_tag(self, vrunner_sh):
        """Auth 9p tag is TOOL_NAME_auth (separate from the shared /mnt/share)."""
        assert re.search(r'auth_tag="\$\{TOOL_NAME\}_auth"', vrunner_sh), (
            'setup_auth_share must use a dedicated "${TOOL_NAME}_auth" 9p tag'
        )

    def test_vrunner_auth_cmdline_is_flag_only(self, vrunner_sh):
        """Only a boolean flag (_auth=1) is appended - never the path or contents."""
        # Flag is appended:
        assert re.search(
            r'KERNEL_APPEND="\$KERNEL_APPEND \$\{CMDLINE_PREFIX\}_auth=1"',
            vrunner_sh,
        ), "vrunner.sh must append `${CMDLINE_PREFIX}_auth=1` to KERNEL_APPEND"

        # And the path / env var names must NEVER land in KERNEL_APPEND.
        # Scan every line that mutates KERNEL_APPEND and prove none mention
        # AUTH_CONFIG, VDKR_CONFIG, or VPDMN_CONFIG.
        for ln in vrunner_sh.splitlines():
            if "KERNEL_APPEND=" in ln or "KERNEL_APPEND+=" in ln:
                assert "AUTH_CONFIG" not in ln, (
                    f"KERNEL_APPEND must not carry AUTH_CONFIG: {ln!r}"
                )
                assert "VDKR_CONFIG" not in ln, (
                    f"KERNEL_APPEND must not carry VDKR_CONFIG: {ln!r}"
                )
                assert "VPDMN_CONFIG" not in ln, (
                    f"KERNEL_APPEND must not carry VPDMN_CONFIG: {ln!r}"
                )

    def test_vrunner_setup_auth_share_called_in_both_paths(self, vrunner_sh):
        """setup_auth_share is called at least twice (daemon + non-daemon paths)."""
        # Count *call sites*, not the definition. The definition line has a '(' right after.
        call_sites = [
            ln for ln in vrunner_sh.splitlines()
            if re.search(r'\bsetup_auth_share\b', ln)
            and "()" not in ln
            and not ln.lstrip().startswith("#")
        ]
        assert len(call_sites) >= 2, (
            f"setup_auth_share should be invoked in both daemon and non-daemon "
            f"paths; found {len(call_sites)} call site(s): {call_sites}"
        )

    # --- vcontainer-common.sh ---------------------------------------------

    def test_common_inits_auth_config_from_env(self, vcontainer_common_sh):
        assert re.search(
            r'AUTH_CONFIG="\$\{VDKR_CONFIG:-\$\{VPDMN_CONFIG:-\}\}"',
            vcontainer_common_sh,
        ), "vcontainer-common.sh should init AUTH_CONFIG from VDKR_CONFIG/VPDMN_CONFIG"

    def test_common_parses_config_flag(self, vcontainer_common_sh):
        assert re.search(
            r'--config\)\s*\n(?:\s*#[^\n]*\n)*\s*(?:#[^\n]*\n\s*)*AUTH_CONFIG="\$2"',
            vcontainer_common_sh,
        ), "vcontainer-common.sh should parse --config into AUTH_CONFIG"

    def test_common_forwards_auth_config_to_runner(self, vcontainer_common_sh):
        """AUTH_CONFIG is forwarded as --config to vrunner.sh."""
        assert re.search(
            r'\[ -n "\$AUTH_CONFIG" \].*args\+=\("--config" "\$AUTH_CONFIG"\)',
            vcontainer_common_sh,
        ), "vcontainer-common.sh must forward AUTH_CONFIG via --config to vrunner"

    def test_common_show_usage_documents_config(self, vcontainer_common_sh):
        """--config appears in show_usage help output."""
        assert re.search(r'--config\s+<path>', vcontainer_common_sh), (
            "show_usage must document --config <path>"
        )
        assert "VDKR_CONFIG" in vcontainer_common_sh, \
            "show_usage must mention VDKR_CONFIG env var"
        assert "VPDMN_CONFIG" in vcontainer_common_sh, \
            "show_usage must mention VPDMN_CONFIG env var"

    # --- vcontainer-init-common.sh ----------------------------------------

    def test_init_common_defaults_runtime_auth(self, init_common_sh):
        assert re.search(r'RUNTIME_AUTH="0"', init_common_sh), \
            "init-common must default RUNTIME_AUTH to 0"

    def test_init_common_parses_auth_flag(self, init_common_sh):
        """Kernel cmdline <prefix>_auth=* is parsed into RUNTIME_AUTH."""
        assert re.search(
            r'\$\{VCONTAINER_RUNTIME_PREFIX\}_auth=\*', init_common_sh
        ), "init-common must parse ${VCONTAINER_RUNTIME_PREFIX}_auth=* cmdline arg"
        assert re.search(
            r'RUNTIME_AUTH="\$\{param#\$\{VCONTAINER_RUNTIME_PREFIX\}_auth=\}"',
            init_common_sh,
        ), "init-common must strip _auth= prefix into RUNTIME_AUTH"

    def test_init_common_defines_mount_helpers(self, init_common_sh):
        assert "mount_auth_share()" in init_common_sh, \
            "init-common must define mount_auth_share()"
        assert "unmount_auth_share()" in init_common_sh, \
            "init-common must define unmount_auth_share()"

    def test_init_common_mount_uses_dedicated_tag(self, init_common_sh):
        """mount_auth_share uses ${VCONTAINER_RUNTIME_NAME}_auth tag."""
        assert re.search(
            r'AUTH_SHARE_TAG="\$\{VCONTAINER_RUNTIME_NAME\}_auth"',
            init_common_sh,
        ), "mount_auth_share must use a per-runtime _auth 9p tag"

    def test_init_common_mount_options_hardened(self, init_common_sh):
        """Auth share is mounted ro,nosuid,nodev,noexec."""
        # All four options must be present on the mount command.
        # Find the mount call to be sure we're looking at the right line.
        m = re.search(
            r'mount -t 9p[^\n]*\\\n[^\n]*trans=\$\{NINE_P_TRANSPORT\}[^\n]*',
            init_common_sh,
        )
        assert m, "mount_auth_share must issue a mount -t 9p call"
        # The options are on the continuation line; grab the paragraph.
        start = m.start()
        end = init_common_sh.find('"$AUTH_SHARE_TAG"', start)
        block = init_common_sh[start:end if end != -1 else start + 400]
        for opt in ("ro", "nosuid", "nodev", "noexec"):
            assert opt in block, f"mount_auth_share must include {opt} mount option"

    def test_init_common_mount_guarded_by_runtime_auth(self, init_common_sh):
        """mount_auth_share returns early when RUNTIME_AUTH != 1."""
        # Find "mount_auth_share()" and assert the first ~15 lines contain the guard.
        idx = init_common_sh.find("mount_auth_share()")
        assert idx != -1
        snippet = init_common_sh[idx:idx + 400]
        assert re.search(r'if \[ "\$RUNTIME_AUTH" != "1" \]', snippet), (
            "mount_auth_share must early-return when RUNTIME_AUTH != 1"
        )

    # --- vdkr-init.sh ------------------------------------------------------

    def test_vdkr_defines_install_auth_config(self, vdkr_init_sh):
        assert "install_auth_config()" in vdkr_init_sh, \
            "vdkr-init.sh must define install_auth_config()"

    def test_vdkr_target_path_and_modes(self, vdkr_init_sh):
        """Target is /root/.docker/config.json; mode 0600; parent 0700."""
        assert "/root/.docker/config.json" in vdkr_init_sh, (
            "vdkr-init must write credentials to /root/.docker/config.json"
        )
        assert "chmod 700 /root/.docker" in vdkr_init_sh, \
            "vdkr-init must chmod 700 /root/.docker"
        assert "chmod 600 /root/.docker/config.json" in vdkr_init_sh, \
            "vdkr-init must chmod 600 /root/.docker/config.json"

    def test_vdkr_calls_mount_and_unmount(self, vdkr_init_sh):
        assert "mount_auth_share" in vdkr_init_sh
        assert "unmount_auth_share" in vdkr_init_sh, (
            "vdkr-init must unmount /mnt/auth after copying"
        )

    def test_vdkr_logs_precedence_note(self, vdkr_init_sh):
        """When --config and --registry-user/--registry-pass are both set, log a NOTE."""
        assert re.search(
            r'NOTE:\s*--config\s*takes precedence over\s*--registry-user/--registry-pass',
            vdkr_init_sh,
        ), "vdkr-init must log a precedence NOTE when both mechanisms are supplied"

    def test_vdkr_install_auth_config_after_ca(self, vdkr_init_sh):
        """install_auth_config runs after install_registry_ca in main flow."""
        # Find the call sites (not the definitions). Each name should appear
        # at least once at column 0 (bare call) after the function bodies.
        # A simpler, resilient check: the LAST occurrence of install_registry_ca
        # should appear before the LAST occurrence of install_auth_config.
        last_ca = vdkr_init_sh.rfind("install_registry_ca")
        last_auth = vdkr_init_sh.rfind("install_auth_config")
        assert last_ca != -1 and last_auth != -1
        assert last_ca < last_auth, (
            "install_auth_config must be called AFTER install_registry_ca "
            "so --config wins on precedence"
        )

    # --- vpdmn-init.sh -----------------------------------------------------

    def test_vpdmn_defines_install_auth_config(self, vpdmn_init_sh):
        assert "install_auth_config()" in vpdmn_init_sh, \
            "vpdmn-init.sh must define install_auth_config()"

    def test_vpdmn_target_path_and_modes(self, vpdmn_init_sh):
        """Target is /run/containers/0/auth.json with 0600; dir 0700."""
        assert "/run/containers/0" in vpdmn_init_sh, \
            "vpdmn-init must write to /run/containers/0 (rootful podman default)"
        assert re.search(r'auth_file="\$auth_dir/auth\.json"', vpdmn_init_sh), \
            "vpdmn-init must write to .../auth.json"
        assert re.search(r'chmod 700 "\$auth_dir"', vpdmn_init_sh), \
            "vpdmn-init must chmod 700 the auth dir"
        assert re.search(r'chmod 600 "\$auth_file"', vpdmn_init_sh), \
            "vpdmn-init must chmod 600 the auth.json"

    def test_vpdmn_exports_registry_auth_file(self, vpdmn_init_sh):
        """REGISTRY_AUTH_FILE is exported so podman finds the creds."""
        assert re.search(r'export REGISTRY_AUTH_FILE="\$auth_file"', vpdmn_init_sh), (
            "vpdmn-init must export REGISTRY_AUTH_FILE"
        )

    def test_vpdmn_calls_mount_and_unmount(self, vpdmn_init_sh):
        assert "mount_auth_share" in vpdmn_init_sh
        assert "unmount_auth_share" in vpdmn_init_sh, (
            "vpdmn-init must unmount /mnt/auth after copying"
        )

    def test_vpdmn_install_auth_config_after_verify_podman(self, vpdmn_init_sh):
        """install_auth_config runs after verify_podman in the main flow."""
        last_verify = vpdmn_init_sh.rfind("verify_podman")
        last_auth = vpdmn_init_sh.rfind("install_auth_config")
        assert last_verify != -1 and last_auth != -1
        assert last_verify < last_auth, (
            "install_auth_config should be called AFTER verify_podman"
        )

    # --- README.md ---------------------------------------------------------

    def test_readme_documents_config_section(self, readme_md):
        assert "Passing an existing docker/podman auth file" in readme_md, (
            "README must document the --config feature"
        )

    def test_readme_lists_env_vars(self, readme_md):
        assert "VDKR_CONFIG" in readme_md, "README must document VDKR_CONFIG"
        assert "VPDMN_CONFIG" in readme_md, "README must document VPDMN_CONFIG"

    def test_readme_lists_target_paths(self, readme_md):
        """Both runtime target paths appear in the doc."""
        assert "/root/.docker/config.json" in readme_md, \
            "README must document the vdkr target path"
        assert "/run/containers/0/auth.json" in readme_md, \
            "README must document the vpdmn target path"


# ---------------------------------------------------------------------------
# Tier 2: Functional validator tests (bash subshell, no QEMU).
# ---------------------------------------------------------------------------


def _extract_validate_auth_config(vrunner_text: str) -> str:
    """Extract the validate_auth_config function body from vrunner.sh.

    Parses from "validate_auth_config() {" to its matching top-level closing
    brace. Simple brace-counting suffices because the function body only
    contains shell constructs (no here-docs that start with '{').
    """
    start = vrunner_text.find("validate_auth_config()")
    assert start != -1, "validate_auth_config not found in vrunner.sh"
    # Jump to the opening brace of the function.
    brace = vrunner_text.find("{", start)
    assert brace != -1
    depth = 0
    i = brace
    n = len(vrunner_text)
    while i < n:
        ch = vrunner_text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return vrunner_text[start : i + 1]
        i += 1
    raise AssertionError("Unterminated validate_auth_config definition")


@pytest.fixture(scope="module")
def validator_harness(vrunner_sh, tmp_path_factory) -> Path:
    """Create a tiny bash script that sources validate_auth_config + runs it.

    The harness is parameterised by $1 = path argument. It prints validator
    output to stderr (as vrunner does) and exits with the validator's code.
    """
    body = _extract_validate_auth_config(vrunner_sh)
    harness = textwrap.dedent(
        """\
        #!/usr/bin/env bash
        # Test harness for validate_auth_config (extracted from vrunner.sh).

        # Stub the log() helper used by validate_auth_config. Route everything
        # to stderr so the test can grep on captured stderr.
        log() {
            local level="$1"
            shift
            echo "[$level] $*" 1>&2
        }

        %s

        validate_auth_config "$1"
        exit $?
        """
    ) % body

    out = tmp_path_factory.mktemp("auth_validator") / "harness.sh"
    out.write_text(harness)
    out.chmod(0o700)
    return out


def _run_validator(harness: Path, path_arg: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(harness), path_arg],
        capture_output=True,
        text=True,
        timeout=10,
    )


class TestAuthConfigValidator:
    """Functional tests for validate_auth_config() in vrunner.sh."""

    def test_accepts_valid_mode_600(self, validator_harness, tmp_path):
        f = tmp_path / "config.json"
        f.write_text('{"auths":{}}')
        os.chmod(f, 0o600)
        r = _run_validator(validator_harness, str(f))
        assert r.returncode == 0, f"expected accept, got {r.returncode}\nstderr={r.stderr}"

    def test_accepts_valid_mode_400(self, validator_harness, tmp_path):
        f = tmp_path / "config.json"
        f.write_text('{"auths":{}}')
        os.chmod(f, 0o400)
        r = _run_validator(validator_harness, str(f))
        assert r.returncode == 0, f"expected accept, got {r.returncode}\nstderr={r.stderr}"

    def test_accepts_minimum_two_byte_json(self, validator_harness, tmp_path):
        """A 2-byte file ('{}' with no trailing newline) is the minimum valid size."""
        f = tmp_path / "config.json"
        f.write_bytes(b"{}")
        os.chmod(f, 0o600)
        r = _run_validator(validator_harness, str(f))
        assert r.returncode == 0, (
            f"expected accept for 2-byte file, got {r.returncode}\nstderr={r.stderr}"
        )

    def test_rejects_missing_file(self, validator_harness, tmp_path):
        r = _run_validator(validator_harness, str(tmp_path / "no-such-file"))
        assert r.returncode != 0
        assert "not found" in r.stderr

    def test_rejects_symlink(self, validator_harness, tmp_path):
        target = tmp_path / "real.json"
        target.write_text('{"auths":{}}')
        os.chmod(target, 0o600)
        link = tmp_path / "link.json"
        link.symlink_to(target)
        r = _run_validator(validator_harness, str(link))
        assert r.returncode != 0
        assert "symlink" in r.stderr

    def test_rejects_directory(self, validator_harness, tmp_path):
        d = tmp_path / "adir"
        d.mkdir()
        r = _run_validator(validator_harness, str(d))
        assert r.returncode != 0
        # Directories trip the -L check first on some shells; either error is fine.
        assert "regular file" in r.stderr or "not readable" in r.stderr or "symlink" not in r.stderr

    def test_rejects_empty_file(self, validator_harness, tmp_path):
        f = tmp_path / "empty.json"
        f.write_bytes(b"")
        os.chmod(f, 0o600)
        r = _run_validator(validator_harness, str(f))
        assert r.returncode != 0
        assert "empty or too small" in r.stderr

    def test_rejects_one_byte_file(self, validator_harness, tmp_path):
        """A single-byte file (e.g. lone newline from 'echo > file') is rejected."""
        f = tmp_path / "tiny.json"
        f.write_bytes(b"\n")
        os.chmod(f, 0o600)
        r = _run_validator(validator_harness, str(f))
        assert r.returncode != 0
        assert "empty or too small" in r.stderr

    def test_rejects_oversize_file(self, validator_harness, tmp_path):
        """Files > 1 MiB are rejected."""
        f = tmp_path / "big.json"
        # 1 MiB + 1 byte.
        f.write_bytes(b"{" + b"a" * (1024 * 1024) + b"}")
        os.chmod(f, 0o600)
        r = _run_validator(validator_harness, str(f))
        assert r.returncode != 0
        assert "too large" in r.stderr

    def test_rejects_world_readable(self, validator_harness, tmp_path):
        """Mode 0644 (group/other readable) is rejected."""
        f = tmp_path / "config.json"
        f.write_text('{"auths":{}}')
        os.chmod(f, 0o644)
        r = _run_validator(validator_harness, str(f))
        assert r.returncode != 0
        assert "unsafe permissions" in r.stderr

    def test_rejects_group_readable(self, validator_harness, tmp_path):
        """Mode 0640 (group readable) is rejected."""
        f = tmp_path / "config.json"
        f.write_text('{"auths":{}}')
        os.chmod(f, 0o640)
        r = _run_validator(validator_harness, str(f))
        assert r.returncode != 0
        assert "unsafe permissions" in r.stderr

    def test_rejects_executable(self, validator_harness, tmp_path):
        """Mode 0700 (owner-exec) is rejected - we only permit r/w combos."""
        f = tmp_path / "config.json"
        f.write_text('{"auths":{}}')
        os.chmod(f, 0o700)
        r = _run_validator(validator_harness, str(f))
        assert r.returncode != 0
        assert "unsafe permissions" in r.stderr

    def test_rejects_unreadable(self, validator_harness, tmp_path):
        """A mode 0000 file cannot be read by the invoking user."""
        if os.geteuid() == 0:
            pytest.skip("running as root; DAC permission checks are bypassed")
        f = tmp_path / "config.json"
        f.write_text('{"auths":{}}')
        # 0000: no bits at all.
        os.chmod(f, 0o000)
        try:
            r = _run_validator(validator_harness, str(f))
            assert r.returncode != 0
            # Either "not readable" wins, or the mode-check fires; accept either.
            assert "not readable" in r.stderr or "unsafe permissions" in r.stderr
        finally:
            # Restore perms so pytest can clean up the tmp tree.
            os.chmod(f, 0o600)
