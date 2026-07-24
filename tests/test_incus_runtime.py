# SPDX-FileCopyrightText: Copyright (C) 2026 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Incus runtime tests - boot container-image-host with incus and verify
system container management.

Build prerequisites (in local.conf):
    require conf/distro/include/meta-virt-host.conf
    require conf/distro/include/container-host-incus.conf
    MACHINE = "qemux86-64"  # or qemuarm64

    bitbake container-image-host

Run:
    pytest tests/test_incus_runtime.py -v --machine qemux86-64

Options:
    --boot-timeout      QEMU boot timeout (default: 120s)
    --no-kvm            Disable KVM acceleration
"""

import os
import re
import time
import pytest

try:
    import pexpect
    PEXPECT_AVAILABLE = True
except ImportError:
    PEXPECT_AVAILABLE = False


pytestmark = [
    pytest.mark.skipif(not PEXPECT_AVAILABLE, reason="pexpect not installed"),
    pytest.mark.incus,
]


@pytest.fixture(scope="module")
def incus_qemu(request):
    """Boot a QEMU VM with incus and return the pexpect session."""
    machine = request.config.getoption("--machine", default="qemux86-64")
    boot_timeout = int(request.config.getoption("--boot-timeout", default="120"))
    no_kvm = request.config.getoption("--no-kvm", default=False)

    builddir = os.environ.get("BUILDDIR", os.path.expanduser("~/poky/build"))

    kvm_opt = "" if no_kvm else "kvm"
    cmd = f"runqemu {machine} nographic slirp {kvm_opt} qemuparams=\"-m 4096\""

    child = pexpect.spawn(f"bash -c 'source {builddir}/oe-init-build-env {builddir} >/dev/null 2>&1 && {cmd}'",
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
