# SPDX-FileCopyrightText: Copyright (C) 2026 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Incus runtime tests - boot container-image-host with incus and verify
system container management.

The tests automatically build container-image-host with CONTAINER_PROFILE=incus
before booting. No local.conf changes needed.

Run:
    pytest tests/test_incus_runtime.py -v --poky-dir /opt/bruce/poky

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


pytestmark = [
    pytest.mark.skipif(not PEXPECT_AVAILABLE, reason="pexpect not installed"),
    pytest.mark.incus,
]


def _run_bitbake(build_dir, recipe, extra_vars=None, timeout=3600):
    """Run bitbake with optional variable overrides via -R conf file."""
    bb_cmd = "bitbake"
    conf_file = None
    if extra_vars:
        conf_file = tempfile.NamedTemporaryFile(
            mode='w', suffix='.conf', prefix='pytest-incus-',
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


@pytest.fixture(scope="module")
def incus_image(request):
    """Build container-image-host with incus profile."""
    poky_dir = Path(request.config.getoption("--poky-dir"))
    bd = request.config.getoption("--build-dir")
    build_dir = Path(bd) if bd else poky_dir / "build"
    result = _run_bitbake(
        build_dir, "container-image-host",
        extra_vars={
            "CONTAINER_PROFILE": "incus",
        },
    )
    if result.returncode != 0:
        pytest.fail(f"Incus image build failed: {result.stderr}")


@pytest.fixture(scope="module")
def incus_qemu(request, incus_image):
    """Build incus image, boot a QEMU VM, and return the pexpect session."""
    machine = request.config.getoption("--machine", default="qemux86-64")
    boot_timeout = int(request.config.getoption("--boot-timeout", default="120"))
    no_kvm = request.config.getoption("--no-kvm", default=False)

    poky_dir = Path(request.config.getoption("--poky-dir"))
    bd = request.config.getoption("--build-dir")
    builddir = str(Path(bd) if bd else poky_dir / "build")

    kvm_opt = "" if no_kvm else "kvm"
    cmd = f"runqemu {machine} container-image-host ext4 nographic slirp {kvm_opt} qemuparams=\"-m 4096\""

    child = pexpect.spawn(f"bash -c 'cd {poky_dir} && source oe-init-build-env {builddir} >/dev/null 2>&1 && {cmd}'",
                          timeout=boot_timeout, encoding="utf-8", logfile=None)

    # Wait for login prompt
    child.expect(r"login:", timeout=boot_timeout)
    child.sendline("root")
    child.expect(r"root@.*[:~#]", timeout=30)

    # Suppress shell integration escape sequences
    child.sendline("export TERM=dumb")
    child.expect(r"root@.*[:~#]", timeout=10)

    yield child

    # Cleanup
    child.sendline("poweroff")
    try:
        child.expect(pexpect.EOF, timeout=30)
    except pexpect.TIMEOUT:
        child.terminate(force=True)


def run_cmd(child, cmd, timeout=60):
    """Run a command and return the output."""
    marker = f"__MARKER_{time.monotonic_ns()}__"
    child.sendline(f"{cmd}; echo {marker} $?")
    child.expect(marker + r" (\d+)", timeout=timeout)
    output = child.before.strip()
    rc = int(child.match.group(1))
    # consume prompt
    child.expect(r"root@.*[:~#]", timeout=10)
    return output, rc


class TestIncusDaemon:
    """Test that incusd starts and is functional."""

    def test_incusd_running(self, incus_qemu):
        """incusd should be running via systemd."""
        output, rc = run_cmd(incus_qemu, "systemctl is-active incus.service")
        assert "active" in output, f"incus.service not active: {output}"

    def test_incus_admin_group(self, incus_qemu):
        """incus-admin group should exist."""
        output, rc = run_cmd(incus_qemu, "getent group incus-admin")
        assert rc == 0, "incus-admin group not found"

    def test_incus_version(self, incus_qemu):
        """incus client should report a version."""
        output, rc = run_cmd(incus_qemu, "incus version")
        assert rc == 0, f"incus version failed: {output}"


class TestIncusInit:
    """Test incus initialization."""

    def test_incus_init_minimal(self, incus_qemu):
        """incus admin init --minimal should succeed."""
        output, rc = run_cmd(incus_qemu, "incus admin init --minimal", timeout=120)
        assert rc == 0, f"incus admin init --minimal failed: {output}"

    def test_incus_network_created(self, incus_qemu):
        """Default network bridge should exist after init."""
        output, rc = run_cmd(incus_qemu, "incus network list")
        assert rc == 0, f"incus network list failed: {output}"


class TestIncusContainer:
    """Test launching and managing a container."""

    def test_launch_alpine(self, incus_qemu):
        """Launch an Alpine container from the images: remote."""
        output, rc = run_cmd(incus_qemu, "incus launch images:alpine/edge incus-test1",
                             timeout=180)
        assert rc == 0, f"incus launch failed: {output}"

    def test_container_running(self, incus_qemu):
        """The launched container should be in RUNNING state."""
        output, rc = run_cmd(incus_qemu, "incus list --format csv -c n,s")
        assert rc == 0
        assert "incus-test1,RUNNING" in output.replace(" ", ""), \
            f"Container not running: {output}"

    def test_exec_in_container(self, incus_qemu):
        """Execute a command inside the container."""
        output, rc = run_cmd(incus_qemu, "incus exec incus-test1 -- cat /etc/os-release")
        assert rc == 0
        assert "Alpine" in output, f"Unexpected os-release: {output}"

    def test_stop_container(self, incus_qemu):
        """Stop the container."""
        output, rc = run_cmd(incus_qemu, "incus stop incus-test1", timeout=30)
        assert rc == 0, f"incus stop failed: {output}"

    def test_delete_container(self, incus_qemu):
        """Delete the stopped container."""
        output, rc = run_cmd(incus_qemu, "incus delete incus-test1", timeout=15)
        assert rc == 0, f"incus delete failed: {output}"

    def test_no_containers_remain(self, incus_qemu):
        """No containers should remain after cleanup."""
        output, rc = run_cmd(incus_qemu, "incus list --format csv")
        assert rc == 0
        assert "incus-test1" not in output
