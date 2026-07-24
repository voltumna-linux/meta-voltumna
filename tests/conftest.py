# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Pytest configuration and fixtures for vdkr, vpdmn and container-cross-install testing.

Usage:
    # Run all tests (default path: /tmp/vcontainer)
    pytest tests/ --vdkr-dir /tmp/vcontainer

    # Run vdkr tests only
    pytest tests/test_vdkr.py -v --vdkr-dir /tmp/vcontainer

    # Run vpdmn tests only
    pytest tests/test_vpdmn.py -v --vdkr-dir /tmp/vcontainer

    # Run with memres pre-started (faster)
    ./tests/memres-test.sh start --vdkr-dir /tmp/vcontainer
    pytest tests/test_vdkr.py --vdkr-dir /tmp/vcontainer --skip-destructive

    # Run specific test
    pytest tests/test_vdkr.py::TestMemresBasic -v --vdkr-dir /tmp/vcontainer

Requirements:
    pip install pytest

Environment:
    VDKR_STANDALONE_DIR: Path to extracted vdkr/vpdmn standalone tarball
    VDKR_ARCH: Architecture to test (x86_64 or aarch64), default: x86_64

Notes:
    - Tests use separate state directories (~/.vdkr-test/, ~/.vpdmn-test/) to avoid
      interfering with user's images in ~/.vdkr/ and ~/.vpdmn/.
    - If memres is already running, tests reuse it and don't stop it at the end.
    - Tests pull required images (alpine) automatically if not present.
"""

import os
import subprocess
import shutil
import tempfile
import signal
import atexit
import pytest
from pathlib import Path


# Test state directories - separate from user's ~/.vdkr/ and ~/.vpdmn/
TEST_STATE_BASE = os.path.expanduser("~/.vdkr-test")
VPDMN_TEST_STATE_BASE = os.path.expanduser("~/.vpdmn-test")

# Track test memres PIDs for cleanup
_test_memres_pids = set()


def _cleanup_test_memres():
    """
    Clean up any test memres processes that may have been left running.
    Called on exit (atexit) and signal handlers.
    """
    for state_base in [TEST_STATE_BASE, VPDMN_TEST_STATE_BASE]:
        for arch_dir in Path(state_base).glob("*"):
            pid_file = arch_dir / "daemon.pid"
            if pid_file.exists():
                try:
                    pid = int(pid_file.read_text().strip())
                    # Check if process is still running
                    if Path(f"/proc/{pid}").exists():
                        os.kill(pid, signal.SIGTERM)
                        # Give it a moment to clean up
                        import time
                        time.sleep(0.5)
                        # Force kill if still running
                        if Path(f"/proc/{pid}").exists():
                            os.kill(pid, signal.SIGKILL)
                except (ValueError, ProcessLookupError, PermissionError):
                    pass
                # Remove stale PID file
                try:
                    pid_file.unlink()
                except OSError:
                    pass


def _signal_handler(signum, frame):
    """Handle SIGINT/SIGTERM by cleaning up test memres before exit."""
    _cleanup_test_memres()
    # Re-raise the signal to trigger default behavior
    signal.signal(signum, signal.SIG_DFL)
    os.kill(os.getpid(), signum)


# Register cleanup handlers
atexit.register(_cleanup_test_memres)
signal.signal(signal.SIGINT, _signal_handler)
signal.signal(signal.SIGTERM, _signal_handler)


# Ports used by tests that need to be free
TEST_PORTS = [8080, 8081, 8082, 8888, 8001, 8002, 9999, 7777, 6666]


def _cleanup_orphan_qemu_on_ports():
    """
    Kill any QEMU processes holding ports used by tests.
    This handles cases where a previous test run or manual testing left
    orphan QEMU processes that would block test port bindings.
    """
    import re

    try:
        # Get listening sockets
        result = subprocess.run(
            ["ss", "-tlnp"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode != 0:
            return

        for line in result.stdout.splitlines():
            # Check if any test port is in use
            for port in TEST_PORTS:
                if f":{port}" in line and "qemu" in line.lower():
                    # Extract PID from ss output (format: users:(("qemu...",pid=12345,fd=...)))
                    match = re.search(r'pid=(\d+)', line)
                    if match:
                        pid = int(match.group(1))
                        try:
                            os.kill(pid, signal.SIGTERM)
                            import time
                            time.sleep(0.5)
                            # Force kill if still running
                            if Path(f"/proc/{pid}").exists():
                                os.kill(pid, signal.SIGKILL)
                        except (ProcessLookupError, PermissionError):
                            pass
                    break
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass


def pytest_addoption(parser):
    """Add custom command line options."""
    # vdkr/vpdmn options
    parser.addoption(
        "--vdkr-dir",
        action="store",
        default=os.environ.get("VDKR_STANDALONE_DIR", "/tmp/vcontainer"),
        help="Path to vcontainer standalone directory",
    )
    parser.addoption(
        "--arch",
        action="store",
        default=os.environ.get("VDKR_ARCH", "x86_64"),
        choices=["x86_64", "aarch64"],
        help="Target architecture to test",
    )
    parser.addoption(
        "--oci-image",
        action="store",
        default=os.environ.get("TEST_OCI_IMAGE"),
        help="Path to OCI image for import tests",
    )
    parser.addoption(
        "--skip-destructive",
        action="store_true",
        default=False,
        help="Skip tests that stop memres or clean state (useful when reusing test memres)",
    )
    # container-cross-install options
    parser.addoption(
        "--poky-dir",
        action="store",
        default=os.environ.get("POKY_DIR", "/opt/bruce/poky"),
        help="Path to poky directory",
    )
    parser.addoption(
        "--build-dir",
        action="store",
        default=os.environ.get("BUILD_DIR"),
        help="Path to build directory",
    )
    parser.addoption(
        "--machine",
        action="store",
        default=os.environ.get("MACHINE", "qemux86-64"),
        help="Target machine",
    )
    parser.addoption(
        "--image",
        action="store",
        default=os.environ.get("TEST_IMAGE", "container-image-host"),
        help="Image to boot for container verification tests",
    )
    parser.addoption(
        "--image-fstype",
        action="store",
        default=os.environ.get("TEST_IMAGE_FSTYPE", "ext4"),
        help="Image filesystem type (default: ext4)",
    )
    parser.addoption(
        "--boot-timeout",
        action="store",
        type=int,
        default=120,
        help="Timeout in seconds for image boot (default: 120)",
    )
    parser.addoption(
        "--no-kvm",
        action="store_true",
        default=False,
        help="Disable KVM acceleration",
    )
    parser.addoption(
        "--fail-stale",
        action="store_true",
        default=False,
        help="Fail if rootfs is stale (OCI containers or bbclass newer than rootfs)",
    )
    parser.addoption(
        "--max-age",
        action="store",
        type=float,
        default=24.0,
        help="Max rootfs age in hours before warning (default: 24)",
    )
    # K3s options
    parser.addoption(
        "--k3s-timeout",
        action="store",
        type=int,
        default=300,
        help="Timeout in seconds for k3s readiness (default: 300)",
    )
    # Container registry options
    parser.addoption(
        "--registry-url",
        action="store",
        default=os.environ.get("TEST_REGISTRY_URL"),
        help="Registry URL for vdkr registry tests (e.g., 10.0.2.2:5000/yocto)",
    )
    parser.addoption(
        "--registry-script",
        action="store",
        default=os.environ.get("CONTAINER_REGISTRY_SCRIPT"),
        help="Path to container-registry.sh script",
    )
    parser.addoption(
        "--skip-registry-network",
        action="store_true",
        default=False,
        help="Skip registry tests that require network access to docker.io",
    )
    parser.addoption(
        "--secure-registry",
        action="store_true",
        default=False,
        help="Run secure registry tests (requires openssl, htpasswd)",
    )


def _cleanup_stale_test_state():
    """
    Clean up stale or corrupt test state directories.
    This ensures tests start with a clean slate if previous runs crashed.
    """
    for state_base in [TEST_STATE_BASE, VPDMN_TEST_STATE_BASE]:
        state_path = Path(state_base)
        if not state_path.exists():
            continue

        for arch_dir in state_path.glob("*"):
            if not arch_dir.is_dir():
                continue

            docker_state = arch_dir / "docker-state.img"
            daemon_pid = arch_dir / "daemon.pid"

            # Check if daemon is actually running
            daemon_running = False
            if daemon_pid.exists():
                try:
                    pid = int(daemon_pid.read_text().strip())
                    daemon_running = Path(f"/proc/{pid}").exists()
                except (ValueError, OSError):
                    pass

            # If daemon not running but state exists, it's stale - clean it
            if not daemon_running and docker_state.exists():
                # Check if docker-state.img needs journal recovery (corrupt)
                try:
                    result = subprocess.run(
                        ["file", str(docker_state)],
                        capture_output=True,
                        text=True,
                        timeout=5
                    )
                    if "needs journal recovery" in result.stdout:
                        # State is corrupt, clean it up
                        shutil.rmtree(arch_dir, ignore_errors=True)
                except (subprocess.TimeoutExpired, FileNotFoundError):
                    pass


@pytest.fixture(scope="session", autouse=True)
def cleanup_orphan_qemu():
    """Clean up orphan QEMU processes and stale test state at session start."""
    _cleanup_orphan_qemu_on_ports()
    _cleanup_stale_test_state()
    yield
    # Also clean up at end of session
    _cleanup_orphan_qemu_on_ports()


@pytest.fixture(scope="session")
def vdkr_dir(request):
    """Path to vdkr standalone directory."""
    path = Path(request.config.getoption("--vdkr-dir"))
    if not path.exists():
        pytest.skip(f"vdkr standalone directory not found: {path}")
    return path


@pytest.fixture(scope="session")
def arch(request):
    """Target architecture."""
    return request.config.getoption("--arch")


@pytest.fixture(scope="session")
def vdkr_bin(vdkr_dir, arch):
    """Path to vdkr binary for the target architecture.

    Tries arch-specific symlink first (vdkr-x86_64), then main vdkr binary.
    """
    # Try arch-specific symlink first
    binary = vdkr_dir / f"vdkr-{arch}"
    if binary.exists():
        return binary

    # Fall back to main vdkr binary
    binary = vdkr_dir / "vdkr"
    if binary.exists():
        return binary

    pytest.skip(f"vdkr binary not found: {vdkr_dir}/vdkr or {vdkr_dir}/vdkr-{arch}")


@pytest.fixture(scope="session")
def test_state_dir(arch):
    """Test-specific state directory to avoid interfering with user's state."""
    state_dir = Path(TEST_STATE_BASE) / arch
    state_dir.mkdir(parents=True, exist_ok=True)
    return state_dir


@pytest.fixture(scope="session")
def vdkr_env(vdkr_dir):
    """Environment variables for running vdkr."""
    env = os.environ.copy()

    # Source init-env.sh equivalent
    # Ensure vdkr_dir is a string for PATH concatenation
    vdkr_path = str(vdkr_dir)

    # Support both old layout (qemu/, lib/) and new SDK layout (sysroots/)
    sysroot_dir = vdkr_dir / "sysroots" / "x86_64-pokysdk-linux"
    if sysroot_dir.exists():
        # New SDK layout: sysroots/x86_64-pokysdk-linux/usr/bin/
        env["PATH"] = f"{vdkr_path}:{sysroot_dir}/usr/bin:/usr/bin:/bin:{env.get('PATH', '')}"
        # No LD_LIBRARY_PATH needed - SDK uses proper RPATH
    else:
        # Old layout: qemu/, lib/
        env["PATH"] = f"{vdkr_path}:{vdkr_path}/qemu:/usr/bin:/bin:{env.get('PATH', '')}"
        env["LD_LIBRARY_PATH"] = f"{vdkr_path}/lib:{env.get('LD_LIBRARY_PATH', '')}"

    return env


@pytest.fixture(scope="session")
def oci_image(request):
    """Path to test OCI image, if available."""
    path = request.config.getoption("--oci-image")
    if path:
        path = Path(path)
        if not path.exists():
            pytest.skip(f"OCI image not found: {path}")
        return path
    return None


class VdkrRunner:
    """Helper class for running vdkr commands."""

    def __init__(self, binary: Path, env: dict, arch: str, state_dir: Path):
        self.binary = binary
        self.env = env
        self.arch = arch
        self.state_dir = state_dir
        self._user_memres_was_running = None
        # Check if we're using main vdkr (needs --arch) vs arch-specific symlink
        self._needs_arch_flag = binary.name == "vdkr"

    def run(self, *args, timeout=120, check=True, capture_output=True):
        """Run a vdkr command with test state directory.

        Uses Popen with start_new_session and file-based output to
        prevent daemon background processes from inheriting pipe FDs,
        which causes subprocess.run(capture_output=True) to hang in
        CI/test harness environments.
        """
        cmd = [str(self.binary)]
        if self._needs_arch_flag:
            cmd.extend(["--arch", self.arch])
        cmd.extend(["--state-dir", str(self.state_dir)])
        cmd.extend(list(args))
        with tempfile.TemporaryFile(mode='w+') as out:
            proc = subprocess.Popen(
                cmd, env=self.env,
                stdin=subprocess.DEVNULL,
                stdout=out, stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            try:
                proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
                raise
            out.seek(0)
            output = out.read()
        result = subprocess.CompletedProcess(
            cmd, proc.returncode, stdout=output, stderr="")
        if check and result.returncode != 0:
            error_msg = f"Command failed: {' '.join(cmd)}\n"
            error_msg += f"Exit code: {result.returncode}\n"
            if result.stdout:
                error_msg += f"stdout: {result.stdout}\n"
            if result.stderr:
                error_msg += f"stderr: {result.stderr}\n"
            print(error_msg)
            raise AssertionError(error_msg)
        return result

    def memres_start(self, timeout=120, port_forwards=None, no_registry=False):
        """Start memory resident mode.

        Args:
            timeout: Command timeout in seconds
            port_forwards: List of port forwards, e.g., ["8080:80", "2222:22"]
            no_registry: Disable baked-in registry (default False - registry check is now smart)
        """
        args = ["memres", "start"]
        if no_registry:
            args.append("--no-registry")
        if port_forwards:
            for pf in port_forwards:
                args.extend(["-p", pf])
        # memres start spawns background processes (QEMU VM, idle watchdog)
        # that can inherit pipe FDs from subprocess.run(capture_output=True),
        # causing communicate() to hang indefinitely. Use Popen with
        # file-based output, DEVNULL stdin, and start_new_session to fully
        # isolate the daemon process tree from the test harness.
        cmd = [str(self.binary)]
        if self._needs_arch_flag:
            cmd.extend(["--arch", self.arch])
        cmd.extend(["--state-dir", str(self.state_dir)])
        cmd.extend(args)
        import tempfile
        with tempfile.TemporaryFile(mode='w+') as out:
            proc = subprocess.Popen(
                cmd, env=self.env,
                stdin=subprocess.DEVNULL,
                stdout=out, stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            try:
                proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
                raise
            out.seek(0)
            output = out.read()
        result = subprocess.CompletedProcess(
            cmd, proc.returncode, stdout=output, stderr="")
        return result

    def memres_stop(self, timeout=30):
        """Stop memory resident mode."""
        return self.run("memres", "stop", timeout=timeout, check=False)

    def memres_status(self):
        """Check memory resident status."""
        return self.run("memres", "status", check=False)

    def is_memres_running(self):
        """Check if memres is running (in test state dir)."""
        result = self.memres_status()
        return result.returncode == 0 and "running" in result.stdout.lower()

    def ensure_memres(self, timeout=180):
        """Ensure memres is running, starting it if needed."""
        if not self.is_memres_running():
            result = self.memres_start(timeout=timeout)
            if result.returncode != 0:
                raise RuntimeError(f"Failed to start memres: {result.stderr}")

    def is_user_memres_running(self):
        """Check if user's memres is running (in default ~/.vdkr/)."""
        # Check without --state-dir to see user's memres
        cmd = [str(self.binary)]
        if self._needs_arch_flag:
            cmd.extend(["--arch", self.arch])
        cmd.extend(["memres", "status"])
        result = subprocess.run(
            cmd, env=self.env, capture_output=True, text=True, timeout=10
        )
        return result.returncode == 0 and "running" in result.stdout.lower()

    def images(self, timeout=120):
        """List images."""
        return self.run("images", timeout=timeout)

    def clean(self):
        """Clean state."""
        return self.run("clean", check=False)

    def vimport(self, path, name, timeout=120):
        """Import an OCI image."""
        return self.run("vimport", str(path), name, timeout=timeout)

    def pull(self, image, timeout=180):
        """Pull an image from registry."""
        return self.run("pull", image, timeout=timeout)

    def rmi(self, image, timeout=60):
        """Remove an image."""
        return self.run("rmi", image, timeout=timeout, check=False)

    def vrun(self, image, *cmd, timeout=120):
        """Run a command in a container."""
        return self.run("vrun", image, *cmd, timeout=timeout)

    def inspect(self, target, timeout=60):
        """Inspect an image or container."""
        return self.run("inspect", target, timeout=timeout)

    def save(self, output_file, image, timeout=120):
        """Save an image to a tar file."""
        return self.run("save", "-o", str(output_file), image, timeout=timeout)

    def load(self, input_file, timeout=120):
        """Load an image from a tar file."""
        return self.run("load", "-i", str(input_file), timeout=timeout)

    def has_image(self, image_name):
        """Check if an image exists.

        Uses 'image inspect' for precise matching instead of substring
        search in 'images' output, which can give false positives
        (e.g., 'nginx:alpine' matching search for 'alpine').
        """
        self.ensure_memres()
        # Use image inspect for precise matching - returns 0 if image exists
        ref = image_name if ":" in image_name else f"{image_name}:latest"
        result = self.run("image", "inspect", ref, check=False, capture_output=True)
        return result.returncode == 0

    def ensure_alpine(self, timeout=300):
        """Ensure alpine:latest is available, pulling if necessary."""
        # Ensure memres is running first (in case a previous test stopped it)
        self.ensure_memres()
        if not self.has_image("alpine"):
            self.pull("alpine:latest", timeout=timeout)

    def ensure_busybox(self, timeout=300):
        """Ensure busybox:latest is available, pulling if necessary."""
        # Ensure memres is running first (in case a previous test stopped it)
        self.ensure_memres()
        if not self.has_image("busybox"):
            self.pull("busybox:latest", timeout=timeout)


@pytest.fixture(scope="session")
def vdkr(vdkr_bin, vdkr_env, arch, test_state_dir):
    """VdkrRunner instance for running vdkr commands."""
    return VdkrRunner(vdkr_bin, vdkr_env, arch, test_state_dir)


@pytest.fixture(scope="session")
def memres_session(vdkr):
    """
    Session-scoped fixture that ensures memres is running for tests.
    Uses separate test state directory (~/.vdkr-test/).

    Note: TestMemresBasic tests may stop/restart memres during the session.
    Tests using this fixture should call ensure_memres() or ensure_alpine()
    to guarantee memres is running before executing commands.
    """
    # Check if memres was already running at session start
    was_running_at_start = vdkr.is_memres_running()

    # Ensure memres is running
    vdkr.ensure_memres()

    yield vdkr

    # Only stop memres if it wasn't running when we started
    if not was_running_at_start:
        vdkr.memres_stop()


@pytest.fixture
def temp_dir():
    """Create a temporary directory for test files."""
    tmpdir = tempfile.mkdtemp(prefix="vdkr-test-")
    yield Path(tmpdir)
    shutil.rmtree(tmpdir, ignore_errors=True)


# Markers
def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line(
        "markers", "slow: marks tests as slow (deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line(
        "markers", "memres: marks tests that require memory resident mode"
    )
    config.addinivalue_line(
        "markers", "network: marks tests that require network access"
    )
    config.addinivalue_line(
        "markers", "secure: marks tests that require secure registry mode (TLS/auth)"
    )
    config.addinivalue_line(
        "markers", "boot: marks tests that boot a QEMU image (requires built image)"
    )
    config.addinivalue_line(
        "markers", "k3s: marks k3s runtime tests"
    )
    config.addinivalue_line(
        "markers", "multinode: marks multi-node tests (requires two QEMU VMs)"
    )


@pytest.fixture
def skip_secure(request):
    """Skip if secure registry tests not enabled.

    Use with tests that require secure registry infrastructure:
    - openssl for certificate generation
    - htpasswd for authentication setup
    - CONTAINER_REGISTRY_SECURE=1 baked into script

    Enable with: pytest --secure-registry
    """
    if not request.config.getoption("--secure-registry"):
        pytest.skip("Secure registry tests not enabled (use --secure-registry)")
    return False


# ============================================================================
# vpdmn (Podman) fixtures
# ============================================================================

@pytest.fixture(scope="session")
def vpdmn_bin(vdkr_dir, arch):
    """Path to vpdmn binary for the target architecture.

    Tries arch-specific symlink first (vpdmn-x86_64), then main vpdmn binary.
    """
    # Try arch-specific symlink first
    binary = vdkr_dir / f"vpdmn-{arch}"
    if binary.exists():
        return binary

    # Fall back to main vpdmn binary
    binary = vdkr_dir / "vpdmn"
    if binary.exists():
        return binary

    pytest.skip(f"vpdmn binary not found: {vdkr_dir}/vpdmn or {vdkr_dir}/vpdmn-{arch}")


@pytest.fixture(scope="session")
def vpdmn_test_state_dir(arch):
    """Test-specific state directory for vpdmn to avoid interfering with user's state."""
    state_dir = Path(VPDMN_TEST_STATE_BASE) / arch
    state_dir.mkdir(parents=True, exist_ok=True)
    return state_dir


class VpdmnRunner:
    """Helper class for running vpdmn commands."""

    def __init__(self, binary: Path, env: dict, arch: str, state_dir: Path):
        self.binary = binary
        self.env = env
        self.arch = arch
        self.state_dir = state_dir
        self._user_memres_was_running = None
        # Check if we're using main vpdmn (needs --arch) vs arch-specific symlink
        self._needs_arch_flag = binary.name == "vpdmn"

    def run(self, *args, timeout=120, check=True, capture_output=True):
        """Run a vpdmn command with test state directory."""
        cmd = [str(self.binary)]
        if self._needs_arch_flag:
            cmd.extend(["--arch", self.arch])
        cmd.extend(["--state-dir", str(self.state_dir)])
        cmd.extend(list(args))
        result = subprocess.run(
            cmd,
            env=self.env,
            timeout=timeout,
            check=False,  # Don't raise immediately, check manually for better error messages
            capture_output=capture_output,
            text=True,
        )
        if check and result.returncode != 0:
            error_msg = f"Command failed: {' '.join(cmd)}\n"
            error_msg += f"Exit code: {result.returncode}\n"
            if result.stdout:
                error_msg += f"stdout: {result.stdout}\n"
            if result.stderr:
                error_msg += f"stderr: {result.stderr}\n"
            # Print error so it's visible in test output
            print(error_msg)
            raise AssertionError(error_msg)
        return result

    def memres_start(self, timeout=120, port_forwards=None, no_registry=False):
        """Start memory resident mode.

        Args:
            timeout: Command timeout in seconds
            port_forwards: List of port forwards, e.g., ["8080:80", "2222:22"]
            no_registry: Disable baked-in registry (default False - registry check is now smart)
        """
        args = ["memres", "start"]
        if no_registry:
            args.append("--no-registry")
        if port_forwards:
            for pf in port_forwards:
                args.extend(["-p", pf])
        # memres start spawns background processes (QEMU VM, idle watchdog)
        # that can inherit pipe FDs from subprocess.run(capture_output=True),
        # causing communicate() to hang indefinitely. Use Popen with
        # file-based output, DEVNULL stdin, and start_new_session to fully
        # isolate the daemon process tree from the test harness.
        cmd = [str(self.binary)]
        if self._needs_arch_flag:
            cmd.extend(["--arch", self.arch])
        cmd.extend(["--state-dir", str(self.state_dir)])
        cmd.extend(args)
        import tempfile
        with tempfile.TemporaryFile(mode='w+') as out:
            proc = subprocess.Popen(
                cmd, env=self.env,
                stdin=subprocess.DEVNULL,
                stdout=out, stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            try:
                proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
                raise
            out.seek(0)
            output = out.read()
        result = subprocess.CompletedProcess(
            cmd, proc.returncode, stdout=output, stderr="")
        return result

    def memres_stop(self, timeout=30):
        """Stop memory resident mode."""
        return self.run("memres", "stop", timeout=timeout, check=False)

    def memres_status(self):
        """Check memory resident status."""
        return self.run("memres", "status", check=False)

    def is_memres_running(self):
        """Check if memres is running (in test state dir)."""
        result = self.memres_status()
        return result.returncode == 0 and "running" in result.stdout.lower()

    def ensure_memres(self, timeout=180):
        """Ensure memres is running, starting it if needed."""
        if not self.is_memres_running():
            result = self.memres_start(timeout=timeout)
            if result.returncode != 0:
                raise RuntimeError(f"Failed to start memres: {result.stderr}")

    def images(self, timeout=120):
        """List images."""
        return self.run("images", timeout=timeout)

    def clean(self):
        """Clean state."""
        return self.run("clean", check=False)

    def vimport(self, path, name, timeout=120):
        """Import an OCI image."""
        return self.run("vimport", str(path), name, timeout=timeout)

    def pull(self, image, timeout=180):
        """Pull an image from registry."""
        return self.run("pull", image, timeout=timeout)

    def rmi(self, image, timeout=60):
        """Remove an image."""
        return self.run("rmi", image, timeout=timeout, check=False)

    def vrun(self, image, *cmd, timeout=120):
        """Run a command in a container."""
        return self.run("vrun", image, *cmd, timeout=timeout)

    def inspect(self, target, timeout=60):
        """Inspect an image or container."""
        return self.run("inspect", target, timeout=timeout)

    def save(self, output_file, image, timeout=120):
        """Save an image to a tar file."""
        return self.run("save", "-o", str(output_file), image, timeout=timeout)

    def load(self, input_file, timeout=120):
        """Load an image from a tar file."""
        return self.run("load", "-i", str(input_file), timeout=timeout)

    def has_image(self, image_name):
        """Check if an image exists.

        Uses 'image inspect' for precise matching instead of substring
        search in 'images' output, which can give false positives
        (e.g., 'nginx:alpine' matching search for 'alpine').
        """
        self.ensure_memres()
        # Use image inspect for precise matching - returns 0 if image exists
        ref = image_name if ":" in image_name else f"{image_name}:latest"
        result = self.run("image", "inspect", ref, check=False, capture_output=True)
        return result.returncode == 0

    def ensure_alpine(self, timeout=300):
        """Ensure alpine:latest is available, pulling if necessary."""
        # Ensure memres is running first (in case a previous test stopped it)
        self.ensure_memres()
        if not self.has_image("alpine"):
            self.pull("alpine:latest", timeout=timeout)

    def ensure_busybox(self, timeout=300):
        """Ensure busybox:latest is available, pulling if necessary."""
        # Ensure memres is running first (in case a previous test stopped it)
        self.ensure_memres()
        if not self.has_image("busybox"):
            self.pull("busybox:latest", timeout=timeout)


@pytest.fixture(scope="session")
def vpdmn(vpdmn_bin, vdkr_env, arch, vpdmn_test_state_dir):
    """VpdmnRunner instance for running vpdmn commands."""
    return VpdmnRunner(vpdmn_bin, vdkr_env, arch, vpdmn_test_state_dir)


@pytest.fixture(scope="session")
def vpdmn_memres_session(vpdmn):
    """
    Session-scoped fixture that ensures memres is running for vpdmn tests.
    Uses separate test state directory (~/.vpdmn-test/).

    Note: TestMemresBasic tests may stop/restart memres during the session.
    Tests using this fixture should call ensure_memres() or ensure_alpine()
    to guarantee memres is running before executing commands.
    """
    # Check if memres was already running at session start
    was_running_at_start = vpdmn.is_memres_running()

    # Ensure memres is running
    vpdmn.ensure_memres()

    yield vpdmn

    # Only stop memres if it wasn't running when we started
    if not was_running_at_start:
        vpdmn.memres_stop()
