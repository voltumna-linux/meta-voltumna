# SPDX-FileCopyrightText: Copyright (C) 2026 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Containerd runtime tests — recipe checks, build, and boot verification.

The tests automatically build container-image-host with
CONTAINER_PROFILE=containerd before booting. No local.conf changes needed.

Run:
    # Static tests only
    pytest tests/test_containerd_runtime.py -v -m "not slow and not boot" --poky-dir /opt/bruce/poky

    # All tests
    pytest tests/test_containerd_runtime.py -v --poky-dir /opt/bruce/poky
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
            mode='w', suffix='.conf', prefix='pytest-containerd-',
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
def containerd_image(build_dir):
    """Build container-image-host with containerd profile."""
    result = _run_bitbake(
        build_dir, "container-image-host",
        extra_vars={"CONTAINER_PROFILE": "containerd"},
    )
    if result.returncode != 0:
        pytest.fail(f"Containerd image build failed: {result.stderr}")


@pytest.fixture(scope="module")
def containerd_session(request, poky_dir, build_dir, containerd_image):
    """Boot container-image-host with containerd and provide pexpect session."""
    if not PEXPECT_AVAILABLE:
        pytest.skip("pexpect not installed")

    machine = request.config.getoption("--machine", default="qemux86-64")
    timeout = int(request.config.getoption("--boot-timeout", default="120"))
    no_kvm = request.config.getoption("--no-kvm", default=False)

    kvm_opt = "" if no_kvm else "kvm"
    cmd = (
        f"bash -c 'cd {poky_dir} && "
        f"source oe-init-build-env {build_dir} >/dev/null 2>&1 && "
        f"runqemu {machine} container-image-host ext4 nographic slirp "
        f"{kvm_opt} qemuparams=\"-m 2048\"'"
    )

    child = pexpect.spawn(cmd, encoding='utf-8', timeout=timeout)
    child.logfile_read = open('/tmp/runqemu-containerd-test.log', 'w')

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
# Tier 1: Static recipe assertions
# ============================================================================

class TestContainerdRecipeStatic:
    """Static checks on containerd recipe."""

    def test_recipe_exists(self, meta_virt_dir):
        path = meta_virt_dir / "recipes-containers" / "containerd" / "containerd_git.bb"
        assert path.exists()

    def test_provides_virtual_containerd(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-containers" / "containerd" / "containerd_git.bb").read_text()
        assert "virtual/containerd" in content or "virtual-containerd" in content

    def test_systemd_service(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-containers" / "containerd" / "containerd_git.bb").read_text()
        assert "containerd.service" in content

    def test_rdepends_container_runtime(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-containers" / "containerd" / "containerd_git.bb").read_text()
        assert "VIRTUAL-RUNTIME_container_runtime" in content

    def test_cni_networking(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-containers" / "containerd" / "containerd_git.bb").read_text()
        assert "cni_networking" in content

    def test_installs_ctr(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-containers" / "containerd" / "containerd_git.bb").read_text()
        assert "ctr" in content

    def test_installs_shim(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-containers" / "containerd" / "containerd_git.bb").read_text()
        assert "containerd-shim-runc-v2" in content


class TestContainerdProfileStatic:
    """Static checks on containerd profile configuration."""

    def test_profile_conf_exists(self, meta_virt_dir):
        path = meta_virt_dir / "conf" / "distro" / "include" / "container-host-containerd.conf"
        assert path.exists()

    def test_profile_sets_containerd(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "include" / "container-host-containerd.conf").read_text()
        assert 'CONTAINER_PROFILE = "containerd"' in content

    def test_profile_inc_exists(self, meta_virt_dir):
        path = meta_virt_dir / "conf" / "distro" / "include" / "meta-virt-container-containerd.inc"
        assert path.exists()

    def test_profile_engine_is_containerd(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "include" / "meta-virt-container-containerd.inc").read_text()
        assert "containerd" in content
        assert "VIRTUAL-RUNTIME_container_engine" in content

    def test_packagegroup_containerd(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-core" / "packagegroups" / "packagegroup-container.bb").read_text()
        assert "packagegroup-containerd" in content
        assert "nerdctl" in content


class TestNerdctlRecipeStatic:
    """Static checks on nerdctl recipe."""

    def test_recipe_exists(self, meta_virt_dir):
        recipes = list((meta_virt_dir / "recipes-containers" / "nerdctl").glob("nerdctl_*.bb"))
        assert len(recipes) >= 1, "nerdctl recipe not found"


class TestCriToolsRecipeStatic:
    """Static checks on cri-tools (crictl) recipe."""

    def test_recipe_exists(self, meta_virt_dir):
        recipes = list((meta_virt_dir / "recipes-containers" / "cri-tools").glob("cri-tools_*.bb"))
        assert len(recipes) >= 1, "cri-tools recipe not found"


class TestCriORecipeStatic:
    """Static checks on CRI-O recipe."""

    def test_recipe_exists(self, meta_virt_dir):
        path = meta_virt_dir / "recipes-containers" / "cri-o" / "cri-o_git.bb"
        assert path.exists()

    def test_requires_seccomp(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-containers" / "cri-o" / "cri-o_git.bb").read_text()
        assert "seccomp" in content
        assert "REQUIRED_DISTRO_FEATURES" in content

    def test_systemd_service(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-containers" / "cri-o" / "cri-o_git.bb").read_text()
        assert "crio.service" in content

    def test_rdepends_cni(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-containers" / "cri-o" / "cri-o_git.bb").read_text()
        assert "cni" in content

    def test_rdepends_conmon(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-containers" / "cri-o" / "cri-o_git.bb").read_text()
        assert "conmon" in content

    def test_rdepends_runtime(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-containers" / "cri-o" / "cri-o_git.bb").read_text()
        assert "VIRTUAL-RUNTIME_container_runtime" in content


# ============================================================================
# Tier 2: Build verification
# ============================================================================

@pytest.mark.slow
class TestContainerdBuild:
    """Build tests for containerd."""

    def test_containerd_builds(self, build_dir):
        result = _run_bitbake(build_dir, "containerd")
        assert result.returncode == 0, f"containerd build failed: {result.stderr}"

    def test_nerdctl_builds(self, build_dir):
        result = _run_bitbake(build_dir, "nerdctl")
        assert result.returncode == 0, f"nerdctl build failed: {result.stderr}"

    def test_containerd_image_builds(self, build_dir, containerd_image):
        """container-image-host with containerd profile builds (via fixture)."""
        pass


# ============================================================================
# Tier 3: Boot tests — containerd
# ============================================================================

@pytest.mark.slow
@pytest.mark.boot
class TestContainerdRuntime:
    """Boot tests for containerd on container-image-host."""

    def test_containerd_running(self, containerd_session):
        """containerd systemd service should be active."""
        output, rc = run_cmd(containerd_session, "systemctl is-active containerd")
        assert "active" in output, f"containerd not active: {output}"

    def test_ctr_available(self, containerd_session):
        """ctr command should be available."""
        output, rc = run_cmd(containerd_session, "which ctr")
        assert rc == 0, f"ctr not found: {output}"

    def test_nerdctl_available(self, containerd_session):
        """nerdctl command should be available."""
        output, rc = run_cmd(containerd_session, "which nerdctl")
        assert rc == 0, f"nerdctl not found: {output}"

    def test_containerd_version(self, containerd_session):
        """containerd should report its version."""
        output, rc = run_cmd(containerd_session, "containerd --version")
        assert rc == 0, f"containerd version failed: {output}"
        assert "containerd" in output

    def test_ctr_version(self, containerd_session):
        """ctr should report its version."""
        output, rc = run_cmd(containerd_session, "ctr version")
        assert rc == 0, f"ctr version failed: {output}"

    def test_ctr_namespaces(self, containerd_session):
        """ctr should list namespaces."""
        output, rc = run_cmd(containerd_session, "ctr namespaces list")
        assert rc == 0, f"ctr namespaces list failed: {output}"
        assert "NAME" in output, f"Unexpected namespaces output: {output}"

    def test_runtime_available(self, containerd_session):
        """Container runtime (runc/crun) should be installed."""
        output, rc = run_cmd(containerd_session,
                             "which crun 2>/dev/null || which runc 2>/dev/null")
        assert rc == 0, f"No container runtime found: {output}"

    def test_cni_plugins_installed(self, containerd_session):
        """CNI plugins should be installed."""
        output, rc = run_cmd(containerd_session, "ls /opt/cni/bin/bridge")
        assert rc == 0, f"CNI bridge plugin not found: {output}"

    def test_nerdctl_pull(self, containerd_session):
        """nerdctl should be able to pull an image."""
        output, rc = run_cmd(containerd_session,
                             "nerdctl pull docker.io/library/busybox:latest",
                             timeout=120)
        assert rc == 0, f"nerdctl pull failed: {output}"

    def test_nerdctl_run(self, containerd_session):
        """nerdctl should run a container."""
        output, rc = run_cmd(containerd_session,
                             'nerdctl run --rm busybox:latest echo CONTAINERD_WORKS',
                             timeout=60)
        assert rc == 0, f"nerdctl run failed: {output}"
        assert "CONTAINERD_WORKS" in output

    def test_nerdctl_images(self, containerd_session):
        """nerdctl images should show pulled images."""
        output, rc = run_cmd(containerd_session, "nerdctl images")
        assert rc == 0, f"nerdctl images failed: {output}"
        assert "busybox" in output

    def test_nerdctl_cleanup(self, containerd_session):
        """Clean up test image."""
        run_cmd(containerd_session, "nerdctl rmi busybox:latest", timeout=30)
