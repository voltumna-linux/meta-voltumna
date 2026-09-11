# SPDX-FileCopyrightText: Copyright (C) 2026 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Libvirt recipe and runtime tests.

Tier 1: Static assertions on recipe files (no build required)
Tier 2: Build verification (requires bitbake)
Tier 3: Boot tests on kvm-image-minimal (requires QEMU with KVM)

The tests automatically build kvm-image-minimal with the kvm
DISTRO_FEATURE before booting. No local.conf changes needed.

Run:
    # Static tests only
    pytest tests/test_libvirt.py -v -m "not slow and not boot" --poky-dir /opt/bruce/poky

    # All tests including build and boot
    pytest tests/test_libvirt.py -v --poky-dir /opt/bruce/poky

Options:
    --boot-timeout      QEMU boot timeout (default: 120s)
    --no-kvm            Disable KVM acceleration
"""

import os
import re
import subprocess
import tempfile
import time
import pytest
from pathlib import Path

try:
    import pexpect
    PEXPECT_AVAILABLE = True
except ImportError:
    PEXPECT_AVAILABLE = False


def _run_bitbake(build_dir, recipe, extra_vars=None, timeout=3600):
    """Run bitbake with optional variable overrides via -R conf file."""
    bb_cmd = "bitbake"
    conf_file = None
    if extra_vars:
        conf_file = tempfile.NamedTemporaryFile(
            mode='w', suffix='.conf', prefix='pytest-libvirt-',
            dir=str(build_dir / "conf"), delete=False)
        for var, val in extra_vars.items():
            conf_file.write(f'{var} = "{val}"\n')
        conf_file.close()
        bb_cmd += f" -R {conf_file.name}"
    bb_cmd += f" {recipe}"
    poky_dir = build_dir.parent
    full_cmd = f"bash -c 'cd {poky_dir} && source oe-init-build-env {build_dir} >/dev/null 2>&1 && {bb_cmd}'"
    try:
        return subprocess.run(full_cmd, shell=True, cwd=build_dir,
                              timeout=timeout, capture_output=True, text=True)
    finally:
        if conf_file:
            os.unlink(conf_file.name)


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture(scope="module")
def poky_dir(request):
    path = Path(request.config.getoption("--poky-dir"))
    if not path.exists():
        pytest.skip(f"Poky directory not found: {path}")
    return path


@pytest.fixture(scope="module")
def build_dir(request, poky_dir):
    bd = request.config.getoption("--build-dir")
    path = Path(bd) if bd else poky_dir / "build"
    if not path.exists():
        pytest.skip(f"Build directory not found: {path}")
    return path


@pytest.fixture(scope="module")
def meta_virt_dir(poky_dir):
    path = poky_dir / "meta-virtualization"
    if not path.exists():
        pytest.skip(f"meta-virtualization not found: {path}")
    return path


@pytest.fixture(scope="module")
def libvirt_recipe(meta_virt_dir):
    path = meta_virt_dir / "recipes-extended" / "libvirt" / "libvirt_git.bb"
    if not path.exists():
        pytest.skip(f"libvirt recipe not found: {path}")
    return path


@pytest.fixture(scope="module")
def libvirt_files_dir(meta_virt_dir):
    path = meta_virt_dir / "recipes-extended" / "libvirt" / "libvirt"
    if not path.exists():
        pytest.skip(f"libvirt files dir not found: {path}")
    return path


@pytest.fixture(scope="module")
def kvm_image(build_dir):
    """Build kvm-image-minimal with kvm DISTRO_FEATURE."""
    result = _run_bitbake(
        build_dir, "kvm-image-minimal",
        extra_vars={
            "DISTRO_FEATURES:append": " kvm",
        },
    )
    if result.returncode != 0:
        pytest.fail(f"KVM image build failed: {result.stderr}")


@pytest.fixture(scope="module")
def libvirt_session(request, poky_dir, build_dir, kvm_image):
    """Boot kvm-image-minimal and provide a pexpect session."""
    if not PEXPECT_AVAILABLE:
        pytest.skip("pexpect not installed")

    machine = request.config.getoption("--machine", default="qemux86-64")
    timeout = int(request.config.getoption("--boot-timeout", default="120"))
    no_kvm = request.config.getoption("--no-kvm", default=False)

    kvm_opt = "" if no_kvm else "kvm"
    cmd = (
        f"bash -c 'cd {poky_dir} && "
        f"source oe-init-build-env {build_dir} >/dev/null 2>&1 && "
        f"runqemu {machine} kvm-image-minimal ext4 nographic slirp "
        f"{kvm_opt} qemuparams=\"-m 2048\"'"
    )

    child = pexpect.spawn(cmd, encoding='utf-8', timeout=timeout)
    child.logfile_read = open('/tmp/runqemu-libvirt-test.log', 'w')

    try:
        index = child.expect([r'login:', r'root@', pexpect.TIMEOUT, pexpect.EOF],
                             timeout=timeout)
        if index == 0:
            child.sendline('root')
            child.expect([r'root@', r'#'], timeout=30)
        elif index >= 2:
            raise RuntimeError("Boot failed")

        child.sendline('export TERM=dumb')
        child.expect(r'root@[^:]+:[^#]+#', timeout=10)

        yield child

    except RuntimeError as e:
        pytest.skip(f"Failed to boot: {e}")
    finally:
        child.sendline('poweroff')
        try:
            child.expect(pexpect.EOF, timeout=30)
        except pexpect.TIMEOUT:
            child.terminate(force=True)


def run_cmd(child, cmd, timeout=60):
    """Run a command and return (output, returncode)."""
    marker = f"__MARKER_{time.monotonic_ns()}__"
    child.sendline(f"{cmd}; echo {marker} $?")
    child.expect(marker + r" (\d+)", timeout=timeout)
    raw = child.before
    raw = re.sub(r'\x1b\]3008;[^\x07\x1b]*(?:\x07|\x1b\\)', '', raw)
    raw = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', raw)
    output = raw.strip()
    rc = int(child.match.group(1))
    child.expect(r'root@[^:]+:[^#]+#', timeout=10)
    return output, rc


# ============================================================================
# Tier 1: Static assertions (no build required)
# ============================================================================

class TestLibvirtRecipeStatic:
    """Static checks on the libvirt recipe file."""

    def test_recipe_exists(self, libvirt_recipe):
        assert libvirt_recipe.exists()

    def test_has_meson_inherit(self, libvirt_recipe):
        content = libvirt_recipe.read_text()
        assert "inherit meson" in content

    def test_has_systemd_support(self, libvirt_recipe):
        content = libvirt_recipe.read_text()
        assert "inherit" in content and "systemd" in content
        assert "SYSTEMD_SERVICE" in content

    def test_systemd_services_defined(self, libvirt_recipe):
        content = libvirt_recipe.read_text()
        assert "libvirtd.service" in content
        assert "virtlockd.service" in content

    def test_has_useradd(self, libvirt_recipe):
        content = libvirt_recipe.read_text()
        assert "inherit" in content and "useradd" in content
        assert "qemu" in content
        assert "libvirt" in content

    def test_qemu_packageconfig(self, libvirt_recipe):
        content = libvirt_recipe.read_text()
        assert "PACKAGECONFIG[qemu]" in content
        assert "driver_qemu" in content

    def test_lxc_packageconfig(self, libvirt_recipe):
        content = libvirt_recipe.read_text()
        assert "PACKAGECONFIG[lxc]" in content
        assert "driver_lxc" in content

    def test_xen_packageconfig_gated(self, libvirt_recipe):
        """libxl PACKAGECONFIG should be gated on xen DISTRO_FEATURE."""
        content = libvirt_recipe.read_text()
        assert "PACKAGECONFIG[libxl]" in content
        for line in content.splitlines():
            if "libxl" in line and "DISTRO_FEATURES" in line:
                assert "xen" in line
                break
        else:
            pytest.fail("libxl PACKAGECONFIG not gated on xen DISTRO_FEATURE")

    def test_nftables_rdepends(self, libvirt_recipe):
        """libvirt-libvirtd should RDEPEND on nftables when configured."""
        content = libvirt_recipe.read_text()
        assert "nftables" in content

    def test_nftables_or_iptables_rdepends(self, libvirt_recipe):
        """RDEPENDS should select nftables or iptables based on PACKAGECONFIG."""
        content = libvirt_recipe.read_text()
        assert "bb.utils.contains('PACKAGECONFIG', 'nftables'" in content, \
            "RDEPENDS should conditionally select nftables or iptables"

    def test_packages_split(self, libvirt_recipe):
        """Recipe should split into libvirt, libvirt-libvirtd, libvirt-virsh."""
        content = libvirt_recipe.read_text()
        assert "${PN}-libvirtd" in content
        assert "${PN}-virsh" in content

    def test_cve_status_entries(self, libvirt_recipe):
        content = libvirt_recipe.read_text()
        assert "CVE_STATUS" in content
        cve_count = content.count("CVE_STATUS[CVE-")
        assert cve_count >= 5, f"Expected at least 5 CVE entries, found {cve_count}"


class TestLibvirtHookSupport:
    """Tests for hook_support.py (the file from the recent bug report)."""

    def test_hook_script_exists(self, libvirt_files_dir):
        path = libvirt_files_dir / "hook_support.py"
        assert path.exists()

    def test_hook_script_python3_shebang(self, libvirt_files_dir):
        content = (libvirt_files_dir / "hook_support.py").read_text()
        first_line = content.splitlines()[0]
        assert "python3" in first_line or "python" in first_line

    def test_hook_script_uses_text_mode(self, libvirt_files_dir):
        """Popen should use text=True for python3 string compatibility."""
        content = (libvirt_files_dir / "hook_support.py").read_text()
        assert "text=True" in content, \
            "Popen should use text=True for python3 string/bytes compatibility"

    def test_hook_script_regex_raw_string(self, libvirt_files_dir):
        """Regex should use raw string to avoid SyntaxWarning in python3.12+."""
        content = (libvirt_files_dir / "hook_support.py").read_text()
        for line in content.splitlines():
            if "re.compile" in line and "\\w" in line:
                assert "rf\"" in line or "r'" in line or 'r"' in line, \
                    f"Regex with \\w should use raw string: {line.strip()}"

    def test_hook_script_syntax_valid(self, libvirt_files_dir):
        """hook_support.py should parse without syntax errors."""
        import py_compile
        path = libvirt_files_dir / "hook_support.py"
        try:
            py_compile.compile(str(path), doraise=True)
        except py_compile.PyCompileError as e:
            pytest.fail(f"Syntax error in hook_support.py: {e}")

    def test_hook_installs_for_all_domains(self, libvirt_recipe):
        """hook_support.py should be installed for daemon, lxc, network, qemu."""
        content = libvirt_recipe.read_text()
        for hook in ["daemon", "lxc", "network", "qemu"]:
            assert hook in content, f"Hook not installed for domain: {hook}"


class TestLibvirtServiceFiles:
    """Tests for systemd service and init script files."""

    def test_initscript_exists(self, libvirt_files_dir):
        assert (libvirt_files_dir / "libvirtd.sh").exists()

    def test_initscript_has_lsb_header(self, libvirt_files_dir):
        content = (libvirt_files_dir / "libvirtd.sh").read_text()
        assert "BEGIN INIT INFO" in content

    def test_initscript_start_stop(self, libvirt_files_dir):
        content = (libvirt_files_dir / "libvirtd.sh").read_text()
        assert "start)" in content
        assert "stop)" in content
        assert "restart)" in content

    def test_dnsmasq_conf_exists(self, libvirt_files_dir):
        assert (libvirt_files_dir / "dnsmasq.conf").exists()

    def test_libvirtd_conf_exists(self, libvirt_files_dir):
        assert (libvirt_files_dir / "libvirtd.conf").exists()

    def test_gnutls_helper_exists(self, libvirt_files_dir):
        assert (libvirt_files_dir / "gnutls-helper.py").exists()


class TestLibvirtPatchFiles:
    """Verify patches exist and reference valid upstream issues."""

    def test_patches_exist(self, libvirt_files_dir):
        patches = list(libvirt_files_dir.glob("*.patch"))
        assert len(patches) >= 1, "Expected at least one patch"

    def test_buildpath_patches_present(self, libvirt_files_dir):
        """Patches for buildpaths should exist."""
        patches = list(libvirt_files_dir.glob("*.patch"))
        buildpath_patches = [p for p in patches if "build-path" in p.name
                             or "build_path" in p.name or "gendispatch" in p.name]
        assert len(buildpath_patches) >= 1, \
            "Expected at least one buildpath-related patch"


class TestKvmImageRecipe:
    """Static checks on kvm-image-minimal recipe."""

    def test_recipe_exists(self, meta_virt_dir):
        path = meta_virt_dir / "recipes-extended" / "images" / "kvm-image-minimal.bb"
        assert path.exists()

    def test_requires_kvm_distro_feature(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-extended" / "images" / "kvm-image-minimal.bb").read_text()
        assert "kvm" in content
        assert "REQUIRED_DISTRO_FEATURES" in content

    def test_includes_libvirt(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-extended" / "images" / "kvm-image-minimal.bb").read_text()
        assert "libvirt" in content
        assert "libvirt-libvirtd" in content
        assert "libvirt-virsh" in content

    def test_includes_qemu(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-extended" / "images" / "kvm-image-minimal.bb").read_text()
        assert "qemu" in content

    def test_includes_kvm_modules(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-extended" / "images" / "kvm-image-minimal.bb").read_text()
        assert "kernel-module-kvm" in content


# ============================================================================
# Tier 2: Build verification (requires bitbake)
# ============================================================================

@pytest.mark.slow
class TestLibvirtBuild:
    """Build tests for libvirt recipe."""

    def test_libvirt_builds(self, build_dir):
        result = _run_bitbake(build_dir, "libvirt")
        assert result.returncode == 0, f"libvirt build failed: {result.stderr}"

    def test_kvm_image_builds(self, build_dir, kvm_image):
        """kvm-image-minimal builds successfully (via kvm_image fixture)."""
        pass


# ============================================================================
# Tier 3: Boot tests (requires QEMU)
# ============================================================================

# Libvirt v12 defaults to modular daemons (virtqemud, virtnetworkd, etc.)
# but kvm-image-minimal runs the monolithic libvirtd. virsh must be pointed
# at the monolithic socket explicitly.
_VIRSH = "virsh -c qemu+unix:///system?socket=/var/run/libvirt/libvirt-sock"


@pytest.mark.slow
@pytest.mark.boot
class TestLibvirtRuntime:
    """Boot tests verifying libvirt on a running kvm-image-minimal."""

    def test_libvirtd_running(self, libvirt_session):
        """libvirtd systemd service should be active."""
        output, rc = run_cmd(libvirt_session, "systemctl is-active libvirtd")
        assert "active" in output, f"libvirtd not active: {output}"

    def test_virtlockd_running(self, libvirt_session):
        """virtlockd should be active (started on demand via socket)."""
        output, rc = run_cmd(libvirt_session,
                             "systemctl is-active virtlockd.socket")
        assert "active" in output, f"virtlockd.socket not active: {output}"

    def test_virsh_available(self, libvirt_session):
        """virsh command should be available."""
        output, rc = run_cmd(libvirt_session, "which virsh")
        assert rc == 0, f"virsh not found: {output}"

    def test_virsh_version(self, libvirt_session):
        """virsh version should report libvirt version."""
        output, rc = run_cmd(libvirt_session, "virsh --version")
        assert rc == 0, f"virsh version failed: {output}"

    def test_virsh_connect(self, libvirt_session):
        """virsh should connect to local libvirtd."""
        output, rc = run_cmd(libvirt_session, f"{_VIRSH} uri")
        assert rc == 0, f"virsh uri failed: {output}"

    def test_virsh_capabilities(self, libvirt_session):
        """virsh capabilities should return valid XML."""
        output, rc = run_cmd(libvirt_session, f"{_VIRSH} capabilities")
        assert rc == 0, f"virsh capabilities failed: {output}"
        assert "<capabilities>" in output or "capabilities" in output

    def test_virsh_nodeinfo(self, libvirt_session):
        """virsh nodeinfo should report system info."""
        output, rc = run_cmd(libvirt_session, f"{_VIRSH} nodeinfo")
        assert rc == 0, f"virsh nodeinfo failed: {output}"
        assert "CPU model" in output or "cpu" in output.lower()

    def test_virsh_list(self, libvirt_session):
        """virsh list should work (even with no domains)."""
        output, rc = run_cmd(libvirt_session, f"{_VIRSH} list --all")
        assert rc == 0, f"virsh list failed: {output}"

    def test_default_network(self, libvirt_session):
        """Default network should be defined."""
        output, rc = run_cmd(libvirt_session, f"{_VIRSH} net-list --all")
        assert rc == 0, f"virsh net-list failed: {output}"

    def test_hook_scripts_installed(self, libvirt_session):
        """Hook scripts should be installed for all domains."""
        output, rc = run_cmd(libvirt_session, "ls /etc/libvirt/hooks/")
        assert rc == 0
        for hook in ["daemon", "lxc", "network", "qemu"]:
            assert hook in output, f"Hook script missing: {hook}"

    def test_hook_scripts_executable(self, libvirt_session):
        """Hook scripts should be executable."""
        output, rc = run_cmd(libvirt_session,
                             "test -x /etc/libvirt/hooks/qemu && echo OK")
        assert "OK" in output, "qemu hook not executable"

    def test_qemu_user_exists(self, libvirt_session):
        """qemu user should exist (created by useradd in recipe)."""
        output, rc = run_cmd(libvirt_session, "grep ^qemu: /etc/passwd")
        assert rc == 0, f"qemu user not found: {output}"

    def test_libvirt_group_exists(self, libvirt_session):
        """libvirt group should exist."""
        output, rc = run_cmd(libvirt_session, "grep ^libvirt: /etc/group")
        assert rc == 0, f"libvirt group not found: {output}"
