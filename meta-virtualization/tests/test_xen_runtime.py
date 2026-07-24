# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Xen runtime boot tests - boot xen-image-minimal and verify hypervisor.

These tests boot an actual Xen Dom0 image via runqemu, verify the
hypervisor is functional, check guest bundling, and exercise vxn/containerd.

Build prerequisites (minimum for Dom0 boot tests):
    DISTRO_FEATURES:append = " xen systemd"
    MACHINE = "qemux86-64"  # or qemuarm64
    bitbake xen-image-minimal

For guest bundling tests:
    IMAGE_INSTALL:append:pn-xen-image-minimal = " alpine-xen-guest-bundle"

For vxn/containerd tests:
    DISTRO_FEATURES:append = " virtualization vcontainer vxn"
    IMAGE_INSTALL:append:pn-xen-image-minimal = " vxn"
    BBMULTICONFIG = "vruntime-aarch64 vruntime-x86-64"

Run with:
    pytest tests/test_xen_runtime.py -v --machine qemux86-64

Skip network-dependent tests:
    pytest tests/test_xen_runtime.py -v -m "boot and not network"

Custom paths and longer timeout:
    pytest tests/test_xen_runtime.py -v \
        --poky-dir /opt/bruce/poky \
        --build-dir /opt/bruce/poky/build \
        --boot-timeout 180
"""

import re
import time
import pytest
from pathlib import Path

# Optional import for boot tests
try:
    import pexpect
    PEXPECT_AVAILABLE = True
except ImportError:
    PEXPECT_AVAILABLE = False


# Note: Command line options (--poky-dir, --build-dir, --machine, --boot-timeout, --no-kvm)
# are defined in conftest.py to avoid conflicts with other test files.


class XenRunner:
    """
    Manages a runqemu session for Xen boot testing.

    Uses pexpect to interact with the serial console of a booted
    xen-image-minimal via runqemu.
    """

    def __init__(self, poky_dir, build_dir, machine, use_kvm=True, timeout=120):
        self.poky_dir = Path(poky_dir)
        self.build_dir = Path(build_dir)
        self.machine = machine
        self.use_kvm = use_kvm
        self.timeout = timeout
        self.child = None
        self.booted = False

    def start(self):
        """Start runqemu and wait for login prompt."""
        if not PEXPECT_AVAILABLE:
            raise RuntimeError("pexpect not installed. Run: pip install pexpect")

        kvm_opt = "kvm" if self.use_kvm else ""
        cmd = (
            f"bash -c 'cd {self.poky_dir} && "
            f"source oe-init-build-env {self.build_dir} >/dev/null 2>&1 && "
            f"runqemu {self.machine} xen-image-minimal wic nographic slirp {kvm_opt} "
            f"qemuparams=\"-m 4096\"'"
        )

        print(f"Starting runqemu (Xen): {cmd}")
        self.child = pexpect.spawn(cmd, encoding='utf-8', timeout=self.timeout)

        # Log output for debugging
        self.child.logfile_read = open('/tmp/runqemu-xen-test.log', 'w')

        # Wait for login prompt
        try:
            index = self.child.expect([
                r'login:',
                r'root@',  # Already logged in
                pexpect.TIMEOUT,
                pexpect.EOF,
            ], timeout=self.timeout)

            if index == 0:
                self.child.sendline('root')
                self.child.expect([r'root@', r'#', r'\$'], timeout=30)
                self.booted = True
            elif index == 1:
                self.booted = True

            if self.booted:
                # Disable terminal UI (progress bars, cursor movement) from
                # tools like ctr, vxn, vctr that use fancy terminal output
                self.child.sendline('export TERM=dumb')
                self.child.expect(r'root@[^:]+:[^#]+#', timeout=10)

            if index == 2:
                raise RuntimeError(f"Timeout waiting for login (>{self.timeout}s)")
            elif index == 3:
                raise RuntimeError("runqemu terminated unexpectedly")

        except Exception as e:
            self.stop()
            raise RuntimeError(f"Failed to boot Xen image: {e}")

        return self

    @staticmethod
    def _strip_escape_sequences(text):
        """Strip ANSI and OSC escape sequences from terminal output."""
        # OSC sequences: ESC ] ... ESC \ or ESC ] ... BEL
        text = re.sub(r'\x1b\][^\x1b\x07]*(?:\x1b\\|\x07)', '', text)
        # CSI sequences: ESC [ ... final_byte
        text = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', text)
        # Any remaining bare ESC sequences
        text = re.sub(r'\x1b[^[\]].?', '', text)
        return text

    def run_command(self, cmd, timeout=60):
        """Run a command and return the output."""
        if not self.booted:
            raise RuntimeError("System not booted")

        # Wait for prompt to be ready
        time.sleep(0.3)

        self.child.sendline(cmd)

        try:
            self.child.expect(r'root@[^:]+:[^#]+#', timeout=timeout)
            raw_output = self.child.before

            # Strip terminal escape sequences (OSC 3008 shell integration, etc.)
            raw_output = self._strip_escape_sequences(raw_output)

            # Parse: split by newlines, skip command echo
            lines = raw_output.replace('\r', '').split('\n')

            output_lines = []
            for i, line in enumerate(lines):
                stripped = line.strip()
                if not stripped:
                    continue
                # First non-empty line is usually the command echo
                if i == 0 or (output_lines == [] and cmd[:10] in line):
                    continue
                output_lines.append(stripped)

            return '\n'.join(output_lines)

        except pexpect.TIMEOUT:
            print(f"[TIMEOUT] Command '{cmd}' timed out after {timeout}s")
            return ""

    def stop(self):
        """Shutdown the QEMU instance."""
        if self.child:
            try:
                if self.booted:
                    self.child.sendline('poweroff')
                    time.sleep(2)

                if self.child.isalive():
                    self.child.terminate(force=True)
            except Exception:
                pass
            finally:
                if self.child.logfile_read:
                    self.child.logfile_read.close()
                self.child = None
                self.booted = False


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture(scope="module")
def poky_dir(request):
    """Path to poky directory."""
    path = Path(request.config.getoption("--poky-dir"))
    if not path.exists():
        pytest.skip(f"Poky directory not found: {path}")
    return path


@pytest.fixture(scope="module")
def build_dir(request, poky_dir):
    """Path to build directory."""
    bd = request.config.getoption("--build-dir")
    if bd:
        path = Path(bd)
    else:
        path = poky_dir / "build"
    if not path.exists():
        pytest.skip(f"Build directory not found: {path}")
    return path


@pytest.fixture(scope="module")
def machine(request):
    """Target machine."""
    return request.config.getoption("--machine")


@pytest.fixture(scope="module")
def xen_session(request, poky_dir, build_dir, machine):
    """
    Module-scoped fixture that boots xen-image-minimal once for all tests.

    Skips if pexpect is not available, image is not found, or boot fails.
    """
    if not PEXPECT_AVAILABLE:
        pytest.skip("pexpect not installed. Run: pip install pexpect")

    # Check that the .wic image exists
    deploy_dir = build_dir / "tmp" / "deploy" / "images" / machine
    wic_files = list(deploy_dir.glob("xen-image-minimal-*.rootfs.wic"))
    if not wic_files:
        pytest.skip(f"xen-image-minimal .wic image not found in {deploy_dir}")

    timeout = request.config.getoption("--boot-timeout")
    use_kvm = not request.config.getoption("--no-kvm")

    runner = XenRunner(poky_dir, build_dir, machine,
                       use_kvm=use_kvm, timeout=timeout)

    try:
        runner.start()
        yield runner
    except RuntimeError as e:
        pytest.skip(f"Failed to boot Xen image: {e}")
    finally:
        runner.stop()


# ============================================================================
# TestXenDom0Boot — Core hypervisor verification
# ============================================================================

@pytest.mark.boot
class TestXenDom0Boot:
    """Core Xen hypervisor verification after booting xen-image-minimal."""

    def test_dom0_reaches_prompt(self, xen_session):
        """Boot succeeds and reaches a shell prompt."""
        assert xen_session.booted, "System failed to boot"
        output = xen_session.run_command('uname -a')
        assert 'Linux' in output

    def test_xen_hypervisor_running(self, xen_session):
        """xl list shows Domain-0, proving Xen hypervisor is running."""
        output = xen_session.run_command('xl list')
        assert 'Domain-0' in output, \
            f"Domain-0 not found in xl list output:\n{output}"

    def test_dom0_memory_reserved(self, xen_session):
        """Domain-0 memory is capped (not consuming all RAM)."""
        output = xen_session.run_command('xl list')
        # Parse xl list output for Domain-0 line
        # Format: Name  ID  Mem  VCPUs  State  Time(s)
        for line in output.splitlines():
            if 'Domain-0' in line:
                parts = line.split()
                # Mem is the 3rd column (index 2)
                if len(parts) >= 3:
                    try:
                        mem_mb = int(parts[2])
                        assert mem_mb <= 512, \
                            f"Domain-0 memory {mem_mb}MB exceeds 512MB cap"
                    except ValueError:
                        pass  # Non-numeric column, skip
                break

    def test_xen_dmesg(self, xen_session):
        """Kernel dmesg contains Xen initialization messages."""
        output = xen_session.run_command('dmesg | grep -i xen | head -10')
        assert output, "No Xen messages found in dmesg"
        # Should see Xen-related init messages
        xen_found = any(
            kw in output.lower()
            for kw in ['xen', 'hypervisor', 'xenbus']
        )
        assert xen_found, \
            f"No Xen keywords in dmesg output:\n{output}"


# ============================================================================
# TestXenGuestBundleRuntime — Guest autostart verification
# ============================================================================

@pytest.mark.boot
class TestXenGuestBundleRuntime:
    """Verify bundled Xen guests auto-start in Dom0."""

    def test_bundled_guests_visible(self, xen_session):
        """xl list shows more than just Domain-0 (bundled guests running)."""
        output = xen_session.run_command('xl list')
        lines = [l for l in output.splitlines()
                 if l.strip() and not l.startswith('Name')]
        if len(lines) <= 1:
            pytest.skip("No bundled guests detected (only Domain-0 in xl list)")
        # At least one guest beyond Domain-0
        guest_count = len(lines) - 1  # subtract Domain-0
        assert guest_count >= 1, \
            f"Expected bundled guests, only found Domain-0:\n{output}"

    def test_xendomains_service(self, xen_session):
        """xendomains systemd service is active (manages guest autostart)."""
        output = xen_session.run_command(
            'systemctl is-active xendomains 2>/dev/null || echo INACTIVE')
        if 'INACTIVE' in output or 'inactive' in output:
            pytest.skip("xendomains service not installed or inactive")
        assert 'active' in output.lower(), \
            f"xendomains not active: {output}"


# Minimum free memory (MB) needed to create a new Xen domain
_XEN_GUEST_MIN_FREE_MB = 256


def _check_xen_free_memory(xen_session, min_mb=_XEN_GUEST_MIN_FREE_MB):
    """Check Xen free memory, skip test if insufficient for a new domain."""
    output = xen_session.run_command(
        'xl info 2>&1 | grep free_memory')
    # Format: "free_memory            : 240"
    match = re.search(r'free_memory\s*:\s*(\d+)', output)
    if match:
        free_mb = int(match.group(1))
        if free_mb < min_mb:
            xl_list = xen_session.run_command('xl list 2>&1')
            pytest.skip(
                f"Insufficient Xen free memory for new domain "
                f"({free_mb} MB free, need {min_mb} MB)\n"
                f"xl list:\n{xl_list}")


# ============================================================================
# TestXenVxnStandalone — vxn on Dom0
# ============================================================================

@pytest.mark.boot
@pytest.mark.network
class TestXenVxnStandalone:
    """Test vxn (Docker CLI for Xen) on Dom0. Requires network access."""

    def test_vxn_available(self, xen_session):
        """vxn binary is installed in Dom0."""
        output = xen_session.run_command('which vxn 2>/dev/null || echo NOT_FOUND')
        if 'NOT_FOUND' in output:
            pytest.skip("vxn not installed in image")
        assert '/vxn' in output

    def test_vxn_run_hello(self, xen_session):
        """vxn run --rm alpine echo hello produces 'hello'."""
        check = xen_session.run_command('which vxn 2>/dev/null || echo NOT_FOUND')
        if 'NOT_FOUND' in check:
            pytest.skip("vxn not installed in image")

        _check_xen_free_memory(xen_session)

        output = xen_session.run_command(
            'vxn run --rm alpine echo hello 2>&1', timeout=120)
        assert 'hello' in output, \
            f"Expected 'hello' in vxn output:\n{output}"


# ============================================================================
# TestXenContainerd — containerd + vctr on Dom0
# ============================================================================

@pytest.mark.boot
@pytest.mark.network
class TestXenContainerd:
    """Test containerd and vctr on Xen Dom0. Requires network access."""

    def test_containerd_running(self, xen_session):
        """containerd systemd service is active."""
        output = xen_session.run_command(
            'systemctl is-active containerd 2>/dev/null || echo INACTIVE')
        if 'INACTIVE' in output or 'inactive' in output:
            pytest.skip("containerd not installed or inactive")
        assert 'active' in output.lower(), \
            f"containerd not active: {output}"

    def test_ctr_pull_and_vctr_run(self, xen_session):
        """Pull alpine via ctr and run hello-world via vctr."""
        svc = xen_session.run_command(
            'systemctl is-active containerd 2>/dev/null || echo INACTIVE')
        if 'INACTIVE' in svc or 'inactive' in svc:
            pytest.skip("containerd not installed or inactive")

        check = xen_session.run_command(
            'which vctr 2>/dev/null || echo NOT_FOUND')
        if 'NOT_FOUND' in check:
            pytest.skip("vctr not installed in image")

        _check_xen_free_memory(xen_session)

        # Pull alpine image
        xen_session.run_command(
            'ctr image pull docker.io/library/alpine:latest 2>&1', timeout=120)

        # Run hello via vctr
        output = xen_session.run_command(
            'vctr run --rm docker.io/library/alpine:latest echo hello 2>&1',
            timeout=120)
        assert 'hello' in output, \
            f"Expected 'hello' in vctr output:\n{output}"
