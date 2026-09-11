# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Xen runtime boot tests - boot xen-image-minimal and verify hypervisor.

These tests boot an actual Xen Dom0 image via runqemu, verify the
hypervisor is functional, check guest bundling, and exercise vxn/containerd.

The tests automatically build xen-image-minimal with the required
DISTRO_FEATURES before booting. No local.conf changes needed.

Run with:
    pytest tests/test_xen_runtime.py -v --poky-dir /opt/bruce/poky

Skip network-dependent tests:
    pytest tests/test_xen_runtime.py -v -m "boot and not network"

Custom paths and longer timeout:
    pytest tests/test_xen_runtime.py -v \
        --poky-dir /opt/bruce/poky \
        --build-dir /opt/bruce/poky/build \
        --boot-timeout 180
"""

import os
import re
import subprocess
import tempfile
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


def _run_bitbake(build_dir, recipe, extra_vars=None, timeout=3600):
    """Run bitbake with optional variable overrides via -R conf file."""
    bb_cmd = "bitbake"
    conf_file = None
    if extra_vars:
        conf_file = tempfile.NamedTemporaryFile(
            mode='w', suffix='.conf', prefix='pytest-xen-',
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
def xen_image(build_dir):
    """Build xen-image-minimal with required distro features + docker engine.

    Self-contained: the fixture installs the container engine + runtime config
    itself (docker-moby + vxn-docker-config: daemon.json wiring vxn-oci-runtime
    as Docker's default runtime, iptables=false), so TestXenDockerBackend
    actually exercises the docker+vxn path instead of silently skipping when
    docker happens not to be in the ambient image. Previously this relied on a
    developer's local.conf pulling docker/podman in, which is not reproducible.

    NB: assumes a clean local.conf -- do NOT also force podman in via
    `IMAGE_INSTALL:append:pn-xen-image-minimal += "... vxn-podman-config"`,
    since podman-docker and docker-moby both provide /usr/bin/docker and will
    conflict at do_rootfs.
    """
    result = _run_bitbake(
        build_dir, "xen-image-minimal",
        extra_vars={
            "DISTRO_FEATURES:append": " xen vxn",
            "IMAGE_INSTALL:append:pn-xen-image-minimal":
                " docker-moby vxn-docker-config",
        },
    )
    if result.returncode != 0:
        pytest.fail(f"Xen image build failed: {result.stderr}")


@pytest.fixture(scope="module")
def xen_session(request, poky_dir, build_dir, machine, xen_image):
    """
    Module-scoped fixture that builds xen-image-minimal and boots it
    once for all tests.

    Skips if pexpect is not available or boot fails.
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


def _vxn_available(xen_session):
    """Check vxn is installed, skip if not."""
    check = xen_session.run_command('which vxn 2>/dev/null || echo NOT_FOUND')
    if 'NOT_FOUND' in check:
        pytest.skip("vxn not installed in image")


def _vxn_cleanup_container(xen_session, name, timeout=30):
    """Best-effort cleanup of a vxn container (stop + rm)."""
    xen_session.run_command(f'vxn stop {name} 2>/dev/null || true', timeout=timeout)
    xen_session.run_command(f'vxn rm {name} 2>/dev/null || true', timeout=timeout)


# ============================================================================
# TestXenVxnLifecycle — Phase 2: per-container DomU lifecycle
# ============================================================================

@pytest.mark.boot
@pytest.mark.network
class TestXenVxnLifecycle:
    """
    Test vxn per-container DomU lifecycle (Phase 2).

    Each test creates a dedicated DomU via 'vxn run -d', exercises one
    lifecycle verb, and cleans up. The key regression target is the
    entrypoint exit-code monitor: busybox ash's wait(1) on a non-child
    PID returned 127 immediately, causing false 'Exited (127)' status.
    """

    def test_run_detached_shows_running(self, xen_session):
        """vxn run -d starts a container that reports Running status."""
        _vxn_available(xen_session)
        _check_xen_free_memory(xen_session)
        name = "lifecycle-run"
        _vxn_cleanup_container(xen_session, name)

        try:
            output = xen_session.run_command(
                f'vxn run -d --name {name} alpine sleep 300 2>&1', timeout=120)
            assert name in output, \
                f"Container name not in run output:\n{output}"

            ps_out = xen_session.run_command('vxn ps 2>&1', timeout=30)
            assert name in ps_out, \
                f"Container {name} not in vxn ps:\n{ps_out}"
            assert 'Running' in ps_out, \
                f"Expected 'Running' status (got Exited — wait-in-subshell bug?):\n{ps_out}"
            assert 'Exited' not in ps_out, \
                f"Container shows Exited prematurely:\n{ps_out}"
        finally:
            _vxn_cleanup_container(xen_session, name)

    def test_exec_in_container(self, xen_session):
        """vxn exec runs commands inside the container chroot."""
        _vxn_available(xen_session)
        _check_xen_free_memory(xen_session)
        name = "lifecycle-exec"
        _vxn_cleanup_container(xen_session, name)

        try:
            xen_session.run_command(
                f'vxn run -d --name {name} alpine sleep 300 2>&1', timeout=120)

            output = xen_session.run_command(
                f'vxn exec {name} cat /etc/os-release 2>&1', timeout=30)
            assert 'Alpine' in output, \
                f"Expected Alpine in exec output:\n{output}"
        finally:
            _vxn_cleanup_container(xen_session, name)

    def test_exec_sees_container_filesystem(self, xen_session):
        """vxn exec sees the container rootfs, not the DomU host rootfs."""
        _vxn_available(xen_session)
        _check_xen_free_memory(xen_session)
        name = "lifecycle-fs"
        _vxn_cleanup_container(xen_session, name)

        try:
            xen_session.run_command(
                f'vxn run -d --name {name} alpine sleep 300 2>&1', timeout=120)

            # Alpine has /etc/alpine-release; the DomU (vdkr rootfs) does not
            output = xen_session.run_command(
                f'vxn exec {name} cat /etc/alpine-release 2>&1', timeout=30)
            assert output.strip(), \
                f"Expected Alpine version string:\n{output}"

            # Should NOT see vxn-init.sh (that's on the DomU host, not in chroot)
            output = xen_session.run_command(
                f'vxn exec {name} ls /vxn-init.sh 2>&1', timeout=30)
            assert 'No such file' in output, \
                f"Container should not see DomU host files:\n{output}"
        finally:
            _vxn_cleanup_container(xen_session, name)

    def test_logs_retrieves_entrypoint_output(self, xen_session):
        """vxn logs returns entrypoint stdout."""
        _vxn_available(xen_session)
        _check_xen_free_memory(xen_session)
        name = "lifecycle-logs"
        _vxn_cleanup_container(xen_session, name)

        try:
            # Use echo so entrypoint produces output then exits
            xen_session.run_command(
                f'vxn run -d --name {name} alpine sh -c "echo log-test-marker; sleep 300" 2>&1',
                timeout=120)
            # Small delay for entrypoint to write output
            time.sleep(2)
            output = xen_session.run_command(
                f'vxn logs {name} 2>&1', timeout=30)
            assert 'log-test-marker' in output, \
                f"Expected 'log-test-marker' in logs:\n{output}"
        finally:
            _vxn_cleanup_container(xen_session, name)

    def test_stop_and_rm(self, xen_session):
        """vxn stop + rm cleans up the container and its DomU."""
        _vxn_available(xen_session)
        _check_xen_free_memory(xen_session)
        name = "lifecycle-stoprm"
        _vxn_cleanup_container(xen_session, name)

        try:
            xen_session.run_command(
                f'vxn run -d --name {name} alpine sleep 300 2>&1', timeout=120)

            # Verify it's running
            ps_out = xen_session.run_command('vxn ps 2>&1', timeout=30)
            assert name in ps_out

            # Stop
            xen_session.run_command(
                f'vxn stop {name} 2>&1', timeout=60)

            # After stop, ps should show Exited or container should be gone
            ps_out = xen_session.run_command('vxn ps 2>&1', timeout=30)
            if name in ps_out:
                assert 'Exited' in ps_out or 'Stopped' in ps_out, \
                    f"Container should be stopped:\n{ps_out}"

            # Remove
            xen_session.run_command(
                f'vxn rm {name} 2>&1', timeout=30)

            # Should no longer appear in ps
            ps_out = xen_session.run_command('vxn ps 2>&1', timeout=30)
            assert name not in ps_out, \
                f"Container should be gone after rm:\n{ps_out}"
        finally:
            _vxn_cleanup_container(xen_session, name)

    def test_multiple_containers(self, xen_session):
        """Multiple detached containers can run simultaneously."""
        _vxn_available(xen_session)
        _check_xen_free_memory(xen_session, min_mb=512)
        names = ["lifecycle-multi1", "lifecycle-multi2"]
        for n in names:
            _vxn_cleanup_container(xen_session, n)

        try:
            for n in names:
                xen_session.run_command(
                    f'vxn run -d --name {n} alpine sleep 300 2>&1', timeout=120)

            ps_out = xen_session.run_command('vxn ps 2>&1', timeout=30)
            for n in names:
                assert n in ps_out, \
                    f"Container {n} not in vxn ps:\n{ps_out}"
            assert ps_out.count('Running') >= 2, \
                f"Expected at least 2 Running containers:\n{ps_out}"
        finally:
            for n in names:
                _vxn_cleanup_container(xen_session, n)


# ============================================================================
# TestXenVxnMemres — Phase 3: persistent DomU (memres)
# ============================================================================

@pytest.mark.boot
@pytest.mark.network
class TestXenVxnMemres:
    """
    Test vxn memres persistent DomU mode (Phase 3).

    Memres keeps a DomU running between containers — subsequent runs
    hot-plug the container disk instead of booting a fresh guest.
    """

    def test_memres_start_status_stop(self, xen_session):
        """memres start/status/stop lifecycle."""
        _vxn_available(xen_session)
        _check_xen_free_memory(xen_session)

        # Clean up any stale memres
        xen_session.run_command('vxn memres stop 2>/dev/null || true', timeout=30)

        try:
            output = xen_session.run_command(
                'vxn memres start 2>&1', timeout=120)
            assert 'Daemon running' in output or 'Socket' in output, \
                f"memres start failed:\n{output}"

            status = xen_session.run_command(
                'vxn memres status 2>&1', timeout=30)
            assert 'Daemon running' in status, \
                f"memres not running:\n{status}"

            # list should show the memres DomU
            list_out = xen_session.run_command(
                'vxn memres list 2>&1', timeout=30)
            assert 'vxn-' in list_out, \
                f"memres domain not in list:\n{list_out}"
        finally:
            xen_session.run_command('vxn memres stop 2>/dev/null || true', timeout=30)

    def test_memres_run_container(self, xen_session):
        """Containers run via memres (hot-plug disk, no fresh boot)."""
        _vxn_available(xen_session)
        _check_xen_free_memory(xen_session)

        xen_session.run_command('vxn memres stop 2>/dev/null || true', timeout=30)

        try:
            xen_session.run_command(
                'vxn memres start 2>&1', timeout=120)

            output = xen_session.run_command(
                'vxn run --rm alpine echo hello-from-memres 2>&1', timeout=120)
            assert 'hello-from-memres' in output, \
                f"Expected 'hello-from-memres':\n{output}"

            # Run a second container to verify memres reuse
            output2 = xen_session.run_command(
                'vxn run --rm alpine cat /etc/os-release 2>&1', timeout=120)
            assert 'Alpine' in output2, \
                f"Expected Alpine in second memres run:\n{output2}"
        finally:
            xen_session.run_command('vxn memres stop 2>/dev/null || true', timeout=30)


# ============================================================================
# TestXenVxnImageCache — Phase 5: host-side OCI image cache
# ============================================================================

@pytest.mark.boot
@pytest.mark.network
class TestXenVxnImageCache:
    """
    Test vxn host-side OCI image cache (Phase 5).

    The cache at ~/.vxn/images/ provides pull/images/rmi/tag/inspect
    commands independent of any container runtime.
    """

    def test_pull_and_list(self, xen_session):
        """vxn pull downloads an image and vxn images lists it."""
        _vxn_available(xen_session)

        output = xen_session.run_command(
            'vxn pull alpine 2>&1', timeout=120)
        assert 'Pulled' in output or 'alpine' in output.lower(), \
            f"Pull failed:\n{output}"

        images = xen_session.run_command('vxn images 2>&1', timeout=30)
        assert 'alpine' in images, \
            f"alpine not in images list:\n{images}"

    def test_tag_and_rmi(self, xen_session):
        """vxn tag creates a new ref; vxn rmi removes it."""
        _vxn_available(xen_session)

        # Ensure alpine is cached
        xen_session.run_command('vxn pull alpine 2>&1', timeout=120)

        # Tag
        output = xen_session.run_command(
            'vxn tag alpine test-tag:v1 2>&1', timeout=30)
        assert 'Tagged' in output, \
            f"Tag failed:\n{output}"

        images = xen_session.run_command('vxn images 2>&1', timeout=30)
        assert 'test-tag' in images, \
            f"test-tag not in images:\n{images}"

        # Remove the tag
        output = xen_session.run_command(
            'vxn rmi test-tag:v1 2>&1', timeout=30)
        assert 'Removed' in output, \
            f"rmi failed:\n{output}"

        images = xen_session.run_command('vxn images 2>&1', timeout=30)
        assert 'test-tag' not in images, \
            f"test-tag still in images after rmi:\n{images}"

    def test_inspect(self, xen_session):
        """vxn image inspect shows OCI config."""
        _vxn_available(xen_session)

        xen_session.run_command('vxn pull alpine 2>&1', timeout=120)

        output = xen_session.run_command(
            'vxn image inspect alpine 2>&1', timeout=30)
        assert 'Cmd' in output, \
            f"Expected OCI config in inspect output:\n{output}"
        assert '/bin/sh' in output, \
            f"Expected /bin/sh in alpine config:\n{output}"


# ============================================================================
# Helpers for Docker/Podman/vdkr/vpdmn backend tests
# ============================================================================

def _docker_available(xen_session):
    """Check Docker is installed and running, skip if not.

    With the self-contained xen_image fixture docker-moby is installed, so a
    'not installed' skip now signals a real problem (engine config missing). If
    the service merely has not started yet, start it before skipping.
    """
    check = xen_session.run_command(
        'which docker 2>/dev/null || echo NOT_FOUND')
    if 'NOT_FOUND' in check:
        pytest.skip("docker not installed in image")
    svc = xen_session.run_command(
        'systemctl is-active docker 2>/dev/null || echo INACTIVE')
    if 'INACTIVE' in svc or 'inactive' in svc:
        # installed but not up yet -- bring it up before giving up
        xen_session.run_command('systemctl start docker 2>&1; sleep 2')
        svc = xen_session.run_command(
            'systemctl is-active docker 2>/dev/null || echo INACTIVE')
        if 'INACTIVE' in svc or 'inactive' in svc:
            pytest.skip("docker service present but failed to start")


def _podman_available(xen_session):
    """Check Podman is installed, skip if not."""
    check = xen_session.run_command(
        'which podman 2>/dev/null || echo NOT_FOUND')
    if 'NOT_FOUND' in check:
        pytest.skip("podman not installed in image")


def _vdkr_available(xen_session):
    """Check vdkr is installed, skip if not."""
    check = xen_session.run_command(
        'which vdkr 2>/dev/null || echo NOT_FOUND')
    if 'NOT_FOUND' in check:
        pytest.skip("vdkr not installed in image")


def _vpdmn_available(xen_session):
    """Check vpdmn is installed, skip if not."""
    check = xen_session.run_command(
        'which vpdmn 2>/dev/null || echo NOT_FOUND')
    if 'NOT_FOUND' in check:
        pytest.skip("vpdmn not installed in image")


# ============================================================================
# TestXenDockerBackend — Phase 4.2: Docker with vxn-oci-runtime
# ============================================================================

@pytest.mark.boot
@pytest.mark.network
class TestXenDockerBackend:
    """
    Test Docker using vxn-oci-runtime as its default OCI runtime.

    Requires vxn-docker-config (daemon.json with vxn as default runtime)
    and docker-moby installed in the image. Containers need --network=none
    because Docker bridge networking is incompatible with VM runtimes.
    """

    def test_docker_vxn_runtime_registered(self, xen_session):
        """Docker reports vxn as default runtime."""
        _docker_available(xen_session)

        output = xen_session.run_command('docker info 2>&1 | grep -i runtime')
        assert 'vxn' in output, \
            f"vxn runtime not in docker info:\n{output}"
        assert 'Default Runtime: vxn' in output or 'default-runtime' in output, \
            f"vxn not set as default runtime:\n{output}"

    def test_docker_run_echo(self, xen_session):
        """docker run --network=none executes in a Xen DomU."""
        _docker_available(xen_session)
        _check_xen_free_memory(xen_session)

        output = xen_session.run_command(
            'docker run --network=none --rm alpine echo hello-from-docker 2>&1',
            timeout=120)
        assert 'hello-from-docker' in output, \
            f"Expected 'hello-from-docker':\n{output}"

    def test_docker_run_os_release(self, xen_session):
        """docker run sees the Alpine container filesystem."""
        _docker_available(xen_session)
        _check_xen_free_memory(xen_session)

        output = xen_session.run_command(
            'docker run --network=none --rm alpine cat /etc/os-release 2>&1',
            timeout=120)
        assert 'Alpine' in output, \
            f"Expected Alpine in output:\n{output}"


# ============================================================================
# TestXenPodmanBackend — Phase 4.2: Podman with vxn-oci-runtime
# ============================================================================

@pytest.mark.boot
@pytest.mark.network
class TestXenPodmanBackend:
    """
    Test Podman using vxn-oci-runtime as its default OCI runtime.

    Requires vxn-podman-config (containers.conf.d with vxn runtime)
    and podman installed in the image. Containers need --network=none
    because Podman bridge networking is incompatible with VM runtimes.
    """

    def test_podman_run_echo(self, xen_session):
        """podman run --network=none executes in a Xen DomU."""
        _podman_available(xen_session)
        _check_xen_free_memory(xen_session)

        output = xen_session.run_command(
            'podman run --network=none --rm alpine echo hello-from-podman 2>&1',
            timeout=120)
        assert 'hello-from-podman' in output, \
            f"Expected 'hello-from-podman':\n{output}"

    def test_podman_run_os_release(self, xen_session):
        """podman run sees the Alpine container filesystem."""
        _podman_available(xen_session)
        _check_xen_free_memory(xen_session)

        output = xen_session.run_command(
            'podman run --network=none --rm alpine cat /etc/os-release 2>&1',
            timeout=120)
        assert 'Alpine' in output, \
            f"Expected Alpine in output:\n{output}"


# ============================================================================
# TestXenVdkr — Phase 4.2: vdkr Dom0 frontend
# ============================================================================

@pytest.mark.boot
@pytest.mark.network
class TestXenVdkr:
    """
    Test vdkr (Docker CLI wrapper for Xen Dom0).

    vdkr auto-detects Xen and uses vxn infrastructure directly.
    Unlike Docker/Podman, no --network=none is needed — vdkr manages
    networking independently via xenbr0.
    """

    def test_vdkr_run_echo(self, xen_session):
        """vdkr run executes in a Xen DomU."""
        _vdkr_available(xen_session)
        _check_xen_free_memory(xen_session)

        output = xen_session.run_command(
            'vdkr run --rm alpine echo hello-from-vdkr 2>&1', timeout=120)
        assert 'hello-from-vdkr' in output, \
            f"Expected 'hello-from-vdkr':\n{output}"

    def test_vdkr_run_os_release(self, xen_session):
        """vdkr run sees the Alpine container filesystem."""
        _vdkr_available(xen_session)
        _check_xen_free_memory(xen_session)

        output = xen_session.run_command(
            'vdkr run --rm alpine cat /etc/os-release 2>&1', timeout=120)
        assert 'Alpine' in output, \
            f"Expected Alpine in output:\n{output}"


# ============================================================================
# TestXenVpdmn — Phase 4.2: vpdmn Dom0 frontend
# ============================================================================

@pytest.mark.boot
@pytest.mark.network
class TestXenVpdmn:
    """
    Test vpdmn (Podman CLI wrapper for Xen Dom0).

    vpdmn auto-detects Xen and uses vxn infrastructure directly.
    Unlike Docker/Podman, no --network=none is needed — vpdmn manages
    networking independently via xenbr0.
    """

    def test_vpdmn_run_echo(self, xen_session):
        """vpdmn run executes in a Xen DomU."""
        _vpdmn_available(xen_session)
        _check_xen_free_memory(xen_session)

        output = xen_session.run_command(
            'vpdmn run --rm alpine echo hello-from-vpdmn 2>&1', timeout=120)
        assert 'hello-from-vpdmn' in output, \
            f"Expected 'hello-from-vpdmn':\n{output}"

    def test_vpdmn_run_os_release(self, xen_session):
        """vpdmn run sees the Alpine container filesystem."""
        _vpdmn_available(xen_session)
        _check_xen_free_memory(xen_session)

        output = xen_session.run_command(
            'vpdmn run --rm alpine cat /etc/os-release 2>&1', timeout=120)
        assert 'Alpine' in output, \
            f"Expected Alpine in output:\n{output}"
