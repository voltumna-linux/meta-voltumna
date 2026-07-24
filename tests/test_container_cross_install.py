# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Tests for container-cross-install - Yocto container bundling system.

These tests verify that container-cross-install correctly bundles
OCI containers into Yocto images.

Run with:
    pytest tests/test_container_cross_install.py -v

Run boot tests (requires built image):
    pytest tests/test_container_cross_install.py::TestBundledContainersBoot -v

Environment variables:
    POKY_DIR: Path to poky directory (default: /opt/bruce/poky)
    BUILD_DIR: Path to build directory (default: $POKY_DIR/build)
    MACHINE: Target machine (default: qemux86-64)

Note: These tests require a configured Yocto build environment.
"""

import os
import re
import subprocess
import time
import pytest
from pathlib import Path

# Optional import for boot tests
try:
    import pexpect
    PEXPECT_AVAILABLE = True
except ImportError:
    PEXPECT_AVAILABLE = False


# Note: Command line options (--poky-dir, --build-dir, --machine, --image, --boot-timeout)
# are defined in conftest.py to avoid conflicts with other test files.


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
    path = request.config.getoption("--build-dir")
    if path:
        path = Path(path)
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
def deploy_dir(build_dir, machine):
    """Path to deploy directory for the machine."""
    path = build_dir / "tmp" / "deploy" / "images" / machine
    if not path.exists():
        pytest.skip(f"Deploy directory not found: {path}")
    return path


@pytest.fixture(scope="module")
def meta_virt_dir(poky_dir):
    """Path to meta-virtualization layer."""
    path = poky_dir / "meta-virtualization"
    if not path.exists():
        pytest.skip(f"meta-virtualization not found: {path}")
    return path


def run_bitbake(build_dir, recipe, task=None, extra_args=None, timeout=1800):
    """Run a bitbake command."""
    cmd = ["bitbake"]
    if task:
        cmd.extend(["-c", task])
    cmd.append(recipe)
    if extra_args:
        cmd.extend(extra_args)

    env = os.environ.copy()
    env["BUILDDIR"] = str(build_dir)

    result = subprocess.run(
        cmd,
        cwd=build_dir,
        env=env,
        timeout=timeout,
        capture_output=True,
        text=True,
    )
    return result


class TestContainerCrossClass:
    """Test container-cross-install.bbclass functionality."""

    def test_class_exists(self, meta_virt_dir):
        """Test that the bbclass file exists."""
        class_file = meta_virt_dir / "classes" / "container-cross-install.bbclass"
        assert class_file.exists(), f"Class file not found: {class_file}"

    def test_class_syntax(self, meta_virt_dir):
        """Basic syntax check on the bbclass."""
        class_file = meta_virt_dir / "classes" / "container-cross-install.bbclass"
        content = class_file.read_text()

        # Check for expected content
        assert "BUNDLED_CONTAINERS" in content
        assert "container_cross_install" in content or "do_rootfs" in content


class TestOCIImageBuild:
    """Test building OCI container images."""

    @pytest.mark.slow
    def test_container_app_base_build(self, build_dir, deploy_dir):
        """Test building container-app-base OCI image."""
        result = run_bitbake(build_dir, "container-app-base", timeout=3600)

        # May not exist in all setups
        if result.returncode != 0:
            if "Nothing PROVIDES" in result.stderr:
                pytest.skip("container-app-base recipe not available")
            pytest.fail(f"Build failed: {result.stderr}")

        # Check OCI output exists
        oci_dirs = list(deploy_dir.glob("*-oci"))
        assert len(oci_dirs) > 0, "No OCI directories found in deploy"


class TestBundledContainers:
    """Test end-to-end container bundling."""

    @pytest.mark.slow
    def test_image_with_bundled_container(self, build_dir, deploy_dir):
        """
        Test building an image with BUNDLED_CONTAINERS set.

        This requires a local.conf with BUNDLED_CONTAINERS defined.
        """
        # Check if BUNDLED_CONTAINERS is configured
        local_conf = build_dir / "conf" / "local.conf"
        if local_conf.exists():
            content = local_conf.read_text()
            if "BUNDLED_CONTAINERS" not in content:
                pytest.skip("BUNDLED_CONTAINERS not configured in local.conf")
        else:
            pytest.skip("local.conf not found")

        # Build the image (this will take a while)
        result = run_bitbake(
            build_dir,
            "core-image-minimal",  # Or whatever image is configured
            task="rootfs",
            timeout=3600,
        )

        if result.returncode != 0:
            pytest.fail(f"Image build failed: {result.stderr}")


class TestRemoteContainerBundle:
    """Test remote container fetching via container-bundle.bbclass.

    These tests verify that containers can be pulled from remote registries
    (like docker.io) during the Yocto build and bundled into target images.
    """

    @pytest.mark.network
    @pytest.mark.slow
    def test_remote_bundle_recipe_builds(self, build_dir):
        """Test that remote-container-bundle recipe builds successfully.

        This verifies:
        1. Recipe syntax is valid
        2. skopeo can fetch the remote container
        3. The container is processed and packaged
        """
        result = run_bitbake(
            build_dir,
            "remote-container-bundle",
            timeout=1800,  # 30 min - network fetch can be slow
        )
        assert result.returncode == 0, f"Build failed: {result.stderr}"

    @pytest.mark.network
    @pytest.mark.slow
    def test_remote_bundle_package_created(self, build_dir, deploy_dir):
        """Test that remote-container-bundle creates the expected package."""
        # First ensure it's built
        result = run_bitbake(
            build_dir,
            "remote-container-bundle",
            timeout=1800,
        )
        if result.returncode != 0:
            pytest.skip(f"Build failed, skipping package check: {result.stderr}")

        # Check for the package in deploy directory
        # Package format depends on PACKAGE_CLASSES config (rpm, deb, or ipk)
        # Note: packages are in tmp/deploy/{rpm,deb,ipk}/, not in images/
        base_deploy = build_dir / "tmp" / "deploy"

        # Only check package directories that exist (user may have configured
        # any of: package_rpm, package_deb, package_ipk)
        pkg_formats = ["rpm", "deb", "ipk"]
        existing_pkg_dirs = [base_deploy / fmt for fmt in pkg_formats
                            if (base_deploy / fmt).exists()]

        if not existing_pkg_dirs:
            pytest.skip(f"No package deploy directories found in {base_deploy}")

        found = False
        for pkg_dir in existing_pkg_dirs:
            packages = list(pkg_dir.rglob("*remote-container-bundle*"))
            if packages:
                found = True
                break

        assert found, (
            f"No remote-container-bundle package found. "
            f"Checked: {[str(d) for d in existing_pkg_dirs]}"
        )

    @pytest.mark.network
    @pytest.mark.slow
    def test_remote_bundle_in_image(self, build_dir, deploy_dir):
        """Test building an image with the remote container bundle.

        This is the full end-to-end test: build an image that includes
        the remote-container-bundle package.
        """
        # Configure local.conf to include remote-container-bundle
        local_conf = build_dir / "conf" / "local.conf"
        if not local_conf.exists():
            pytest.skip("local.conf not found")

        content = local_conf.read_text()

        # Check if already configured
        if "remote-container-bundle" not in content:
            # Add to local.conf (append to avoid conflicts)
            with open(local_conf, "a") as f:
                f.write('\n# Added by pytest for remote container bundle test\n')
                f.write('IMAGE_INSTALL:append:pn-core-image-minimal = " remote-container-bundle"\n')

        # Build the image
        result = run_bitbake(
            build_dir,
            "core-image-minimal",
            task="rootfs",
            timeout=3600,
        )

        if result.returncode != 0:
            pytest.fail(f"Image build failed: {result.stderr}")


class TestVdkrRecipes:
    """Test vdkr/vpdmn recipe builds."""

    @pytest.mark.slow
    def test_vcontainer_tarball(self, build_dir):
        """Test creating vcontainer standalone SDK.

        This builds the SDK-based standalone distribution with vdkr and vpdmn.
        Requires blobs to be built first via multiconfig.
        """
        result = run_bitbake(
            build_dir,
            "vcontainer-tarball",
            timeout=3600,
        )
        assert result.returncode == 0, f"SDK build failed: {result.stderr}"

        # Check SDK installer exists
        sdk_deploy = build_dir / "tmp" / "deploy" / "sdk"
        installers = list(sdk_deploy.glob("vcontainer-standalone*.sh"))
        assert len(installers) > 0, f"No SDK installer found in {sdk_deploy}"

    def test_vdkr_initramfs_create(self, build_dir):
        """Test vdkr-initramfs-create builds."""
        result = run_bitbake(build_dir, "vdkr-initramfs-create")
        assert result.returncode == 0, f"Build failed: {result.stderr}"

    def test_vpdmn_initramfs_create(self, build_dir):
        """Test vpdmn-initramfs-create builds."""
        result = run_bitbake(build_dir, "vpdmn-initramfs-create")
        assert result.returncode == 0, f"Build failed: {result.stderr}"


class TestMulticonfig:
    """Test multiconfig setup for vdkr."""

    def test_multiconfig_files_exist(self, meta_virt_dir):
        """Test that multiconfig files exist."""
        mc_dir = meta_virt_dir / "conf" / "multiconfig"

        aarch64_conf = mc_dir / "vruntime-aarch64.conf"
        x86_64_conf = mc_dir / "vruntime-x86-64.conf"

        assert aarch64_conf.exists() or x86_64_conf.exists(), \
            f"No multiconfig files found in {mc_dir}"

    @pytest.mark.slow
    def test_multiconfig_build(self, build_dir):
        """Test multiconfig image build."""
        # Check if multiconfig is enabled
        local_conf = build_dir / "conf" / "local.conf"
        if local_conf.exists():
            content = local_conf.read_text()
            if "BBMULTICONFIG" not in content:
                pytest.skip("BBMULTICONFIG not configured")
        else:
            pytest.skip("local.conf not found")

        # Try to build multiconfig target
        result = run_bitbake(
            build_dir,
            "mc:vruntime-aarch64:vdkr-rootfs-image",
            timeout=3600,
        )

        if result.returncode != 0:
            if "Invalid multiconfig target" in result.stderr:
                pytest.skip("vruntime-aarch64 multiconfig not available")
            pytest.fail(f"Multiconfig build failed: {result.stderr}")


# ============================================================================
# Boot Tests - Verify bundled containers are visible after boot
# ============================================================================

class RunqemuSession:
    """
    Manages a runqemu session for boot testing.

    Uses pexpect to interact with the serial console.
    """

    def __init__(self, poky_dir, build_dir, machine, image, fstype="ext4",
                 use_kvm=True, timeout=120):
        self.poky_dir = Path(poky_dir)
        self.build_dir = Path(build_dir)
        self.machine = machine
        self.image = image
        self.fstype = fstype
        self.use_kvm = use_kvm
        self.timeout = timeout
        self.child = None
        self.booted = False

    def start(self):
        """Start runqemu and wait for login prompt."""
        if not PEXPECT_AVAILABLE:
            raise RuntimeError("pexpect not installed. Run: pip install pexpect")

        # Build the runqemu command
        # We need to source oe-init-build-env first
        kvm_opt = "kvm" if self.use_kvm else ""
        cmd = (
            f"bash -c 'cd {self.poky_dir} && "
            f"source oe-init-build-env {self.build_dir} >/dev/null 2>&1 && "
            f"runqemu {self.machine} {self.image} {self.fstype} nographic slirp {kvm_opt} "
            f"qemuparams=\"-m 2048\"'"
        )

        print(f"Starting runqemu: {cmd}")
        self.child = pexpect.spawn(cmd, encoding='utf-8', timeout=self.timeout)

        # Log output for debugging
        self.child.logfile_read = open('/tmp/runqemu-test.log', 'w')

        # Wait for login prompt
        try:
            # Look for common login prompts
            index = self.child.expect([
                r'login:',
                r'root@',  # Already logged in
                pexpect.TIMEOUT,
                pexpect.EOF,
            ], timeout=self.timeout)

            if index == 0:
                # Send login
                self.child.sendline('root')
                # Wait for shell prompt
                self.child.expect([r'root@', r'#', r'\$'], timeout=30)
                self.booted = True
            elif index == 1:
                # Already at prompt
                self.booted = True
            elif index == 2:
                raise RuntimeError(f"Timeout waiting for login (>{self.timeout}s)")
            elif index == 3:
                raise RuntimeError("runqemu terminated unexpectedly")

        except Exception as e:
            self.stop()
            raise RuntimeError(f"Failed to boot: {e}")

        return self

    def run_command(self, cmd, timeout=60):
        """Run a command and return the output."""
        if not self.booted:
            raise RuntimeError("System not booted")

        # Wait for prompt to be ready, then clear buffer
        time.sleep(0.3)

        # Send command
        self.child.sendline(cmd)

        try:
            # Wait for the prompt to return (command completed)
            # Match the full prompt pattern: root@hostname:path#
            self.child.expect(r'root@[^:]+:[^#]+#', timeout=timeout)

            # Get everything before the prompt
            raw_output = self.child.before

            # Parse: split by newlines, skip command echo (first line), take the rest
            lines = raw_output.replace('\r', '').split('\n')

            # Filter out empty lines and the command echo
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
                # Try graceful shutdown first
                if self.booted:
                    self.child.sendline('poweroff')
                    time.sleep(2)

                # Force terminate if still running
                if self.child.isalive():
                    self.child.terminate(force=True)
            except Exception:
                pass
            finally:
                if self.child.logfile_read:
                    self.child.logfile_read.close()
                self.child = None
                self.booted = False


@pytest.fixture(scope="module")
def check_rootfs_freshness(build_dir, machine, request):
    """
    Check if the rootfs image is fresh compared to OCI containers and bbclass.
    Warns if rootfs appears stale.
    """
    image = request.config.getoption("--image")
    fstype = request.config.getoption("--image-fstype")

    deploy_dir = build_dir / "tmp" / "deploy" / "images" / machine

    # Find the rootfs image
    rootfs_pattern = f"{image}-{machine}.rootfs.{fstype}"
    rootfs_files = list(deploy_dir.glob(f"{image}-*.rootfs.{fstype}"))

    if not rootfs_files:
        pytest.skip(f"No rootfs image found: {deploy_dir}/{rootfs_pattern}")

    rootfs = max(rootfs_files, key=lambda p: p.stat().st_mtime)
    rootfs_mtime = rootfs.stat().st_mtime
    rootfs_age_hours = (time.time() - rootfs_mtime) / 3600

    # Check OCI container timestamps
    oci_dirs = list(deploy_dir.glob("*-oci"))
    stale_containers = []
    for oci_dir in oci_dirs:
        if oci_dir.is_dir():
            oci_mtime = oci_dir.stat().st_mtime
            if oci_mtime > rootfs_mtime:
                stale_containers.append(oci_dir.name)

    # Check bbclass timestamp
    meta_virt = build_dir.parent / "meta-virtualization"
    bbclass = meta_virt / "classes" / "container-cross-install.bbclass"
    bbclass_newer = False
    if bbclass.exists() and bbclass.stat().st_mtime > rootfs_mtime:
        bbclass_newer = True

    # Get options
    fail_stale = request.config.getoption("--fail-stale")
    max_age = request.config.getoption("--max-age")

    # Generate warnings
    warnings = []
    is_stale = False

    if stale_containers:
        warnings.append(f"OCI containers newer than rootfs: {', '.join(stale_containers)}")
        is_stale = True
    if bbclass_newer:
        warnings.append("container-cross-install.bbclass modified after rootfs was built")
        is_stale = True
    if rootfs_age_hours > max_age:
        warnings.append(f"rootfs is {rootfs_age_hours:.1f} hours old (max: {max_age}h)")

    if warnings:
        warning_msg = (
            f"\n{'='*60}\n"
            f"{'ERROR' if (fail_stale and is_stale) else 'WARNING'}: Rootfs may be stale!\n"
            f"  Image: {rootfs.name}\n"
            f"  Built: {time.ctime(rootfs_mtime)}\n"
            f"  Issues:\n"
        )
        for w in warnings:
            warning_msg += f"    - {w}\n"
        warning_msg += (
            f"\n  To rebuild:\n"
            f"    MACHINE={machine} bitbake {image} -C rootfs\n"
            f"{'='*60}\n"
        )
        print(warning_msg)

        if fail_stale and is_stale:
            pytest.fail("Rootfs is stale. Rebuild with: "
                       f"MACHINE={machine} bitbake {image} -C rootfs")

    return {
        'rootfs': rootfs,
        'age_hours': rootfs_age_hours,
        'stale_containers': stale_containers,
        'bbclass_newer': bbclass_newer,
    }


@pytest.fixture(scope="class")
def runqemu_session(request, poky_dir, build_dir, machine, check_rootfs_freshness):
    """
    Fixture that boots an image and provides a session for running commands.

    The session is shared across all tests in the class for efficiency.
    """
    if not PEXPECT_AVAILABLE:
        pytest.skip("pexpect not installed. Run: pip install pexpect")

    image = request.config.getoption("--image")
    fstype = request.config.getoption("--image-fstype")
    timeout = request.config.getoption("--boot-timeout")
    use_kvm = not request.config.getoption("--no-kvm")

    session = RunqemuSession(poky_dir, build_dir, machine, image,
                             fstype=fstype, use_kvm=use_kvm, timeout=timeout)

    try:
        session.start()
        yield session
    finally:
        session.stop()


def _detect_containers_from_rootfs(build_dir, machine, image):
    """
    Detect bundled containers by checking storage directories in the rootfs.

    Checks:
    1. Docker: /var/lib/docker/image/overlay2/repositories.json
    2. Podman: /var/lib/containers/storage/vfs-images/images.json

    Returns dict with 'docker' and 'podman' lists, or None if no containers found.
    """
    import subprocess
    import json

    docker_containers = []
    podman_containers = []

    # Find the rootfs ext4 image
    deploy_dir = build_dir / "tmp" / "deploy" / "images" / machine
    rootfs_pattern = f"{image}-{machine}.rootfs.ext4"
    rootfs_path = deploy_dir / rootfs_pattern

    if not rootfs_path.exists():
        # Try to find via symlink resolution
        for f in deploy_dir.glob(f"{image}*.ext4"):
            if f.is_symlink() or f.is_file():
                rootfs_path = f
                break

    if not rootfs_path.exists():
        return None

    # Use debugfs to check container storage
    try:
        # Check Docker repositories.json
        result = subprocess.run(
            ['debugfs', '-R', 'cat /var/lib/docker/image/overlay2/repositories.json', str(rootfs_path)],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0 and result.stdout.strip():
            try:
                repos = json.loads(result.stdout)
                # Docker repositories.json format: {"Repositories": {"name:tag": {"name:tag": "sha256:..."}}}
                if 'Repositories' in repos:
                    for name in repos['Repositories'].keys():
                        # Extract just the name part (before :tag)
                        container_name = name.split(':')[0] if ':' in name else name
                        docker_containers.append(container_name)
            except json.JSONDecodeError:
                pass

        # Check Podman images.json
        result = subprocess.run(
            ['debugfs', '-R', 'cat /var/lib/containers/storage/vfs-images/images.json', str(rootfs_path)],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0 and result.stdout.strip():
            try:
                images = json.loads(result.stdout)
                # Podman images.json is a list of image objects with 'names' field
                for img in images:
                    if 'names' in img and img['names']:
                        for name in img['names']:
                            # Extract container name from full reference
                            # e.g., "docker.io/library/container-base:latest" -> "container-base"
                            parts = name.split('/')
                            last_part = parts[-1] if parts else name
                            container_name = last_part.split(':')[0] if ':' in last_part else last_part
                            podman_containers.append(container_name)
            except json.JSONDecodeError:
                pass

        if docker_containers or podman_containers:
            return {
                'docker': list(set(docker_containers)),  # Deduplicate
                'podman': list(set(podman_containers)),
            }

    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    return None


def _check_bundle_packages_in_manifest(build_dir, machine, image):
    """
    Check if any container bundle packages are installed by looking at the manifest.

    Returns True if bundle packages found, False otherwise.
    """
    manifest = build_dir / "tmp" / "deploy" / "images" / machine / f"{image}-{machine}.rootfs.manifest"
    if not manifest.exists():
        return False

    content = manifest.read_text()
    for line in content.splitlines():
        # Bundle packages typically have 'bundle' in the name
        if 'bundle' in line.lower() and 'container' in line.lower():
            return True
    return False


def _parse_bundled_containers_from_local_conf(build_dir):
    """
    Parse legacy BUNDLED_CONTAINERS variable from local.conf.

    Returns dict with 'docker' and 'podman' lists, or None if not configured.
    """
    local_conf = build_dir / "conf" / "local.conf"
    if not local_conf.exists():
        return None

    content = local_conf.read_text()

    docker_containers = []
    podman_containers = []

    for line in content.splitlines():
        line = line.strip()
        if line.startswith('#'):
            continue
        if 'BUNDLED_CONTAINERS' not in line:
            continue

        # Parse the value: "container-oci:runtime container2-oci:runtime"
        match = re.search(r'BUNDLED_CONTAINERS\s*=\s*"([^"]*)"', line)
        if match:
            value = match.group(1)
            for item in value.split():
                if ':' in item:
                    container_oci, runtime = item.split(':', 1)
                    # Extract container name from OCI name
                    # e.g., "container-app-base-latest-oci" -> "container-app-base"
                    name = container_oci.replace('-latest-oci', '').replace('-oci', '')
                    if runtime == 'docker':
                        docker_containers.append(name)
                    elif runtime == 'podman':
                        podman_containers.append(name)

    if docker_containers or podman_containers:
        return {
            'docker': docker_containers,
            'podman': podman_containers,
        }

    return None


@pytest.fixture(scope="module")
def bundled_containers_config(build_dir, request):
    """
    Detect bundled containers from rootfs storage or BUNDLED_CONTAINERS variable.

    Detection order:
    1. Direct detection: Check container storage in rootfs
       (Docker: /var/lib/docker, Podman: /var/lib/containers/storage)
    2. Legacy: Parse BUNDLED_CONTAINERS variable from local.conf

    Returns a dict with:
        - 'docker': list of container names expected in docker
        - 'podman': list of container names expected in podman
    """
    # Get machine and image from pytest options
    machine = request.config.getoption("--machine", default="qemux86-64")
    image = request.config.getoption("--image", default="container-image-host")

    # Try to detect containers directly from rootfs storage
    result = _detect_containers_from_rootfs(build_dir, machine, image)
    if result:
        return result

    # Fallback to legacy BUNDLED_CONTAINERS variable
    result = _parse_bundled_containers_from_local_conf(build_dir)
    if result:
        return result

    # Check if bundle packages are installed but containers not detected
    if _check_bundle_packages_in_manifest(build_dir, machine, image):
        pytest.skip("Bundle packages installed but no containers detected in storage (image may need rebuild)")

    pytest.skip("No container bundles found (no containers in rootfs storage and no BUNDLED_CONTAINERS in local.conf)")


class TestBundledContainersBoot:
    """
    Boot tests to verify bundled containers are visible.

    These tests boot the actual Yocto image and verify that
    `docker images` or `podman images` shows the bundled containers.

    Prerequisites:
        - Image must be built with BUNDLED_CONTAINERS configured
        - pexpect must be installed: pip install pexpect

    Run with:
        pytest tests/test_container_cross_install.py::TestBundledContainersBoot -v

    Options:
        --image IMAGE          Image name to boot (default: core-image-minimal)
        --machine MACHINE      Machine to use (default: qemux86-64)
        --boot-timeout SECS    Timeout for boot (default: 120)
    """

    @pytest.mark.slow
    @pytest.mark.boot
    def test_system_boots(self, runqemu_session):
        """Test that the system boots successfully."""
        assert runqemu_session.booted, "System failed to boot"

        # Basic sanity check
        output = runqemu_session.run_command('uname -a')
        assert 'Linux' in output, f"Unexpected uname output: {output}"

    @pytest.mark.slow
    @pytest.mark.boot
    def test_docker_images_visible(self, runqemu_session, bundled_containers_config):
        """Test that bundled Docker containers are visible."""
        expected = bundled_containers_config['docker']
        if not expected:
            pytest.skip("No Docker containers in bundle packages or BUNDLED_CONTAINERS")

        # Check if docker is available
        output = runqemu_session.run_command('which docker')
        if '/docker' not in output:
            pytest.skip("docker not installed in image")

        # Get docker images
        output = runqemu_session.run_command('docker images', timeout=30)
        print(f"docker images output:\n{output}")

        # Verify each expected container is present
        missing = []
        for container in expected:
            if container not in output:
                missing.append(container)

        assert not missing, f"Missing Docker containers: {missing}\nOutput:\n{output}"

    @pytest.mark.slow
    @pytest.mark.boot
    def test_podman_images_visible(self, runqemu_session, bundled_containers_config):
        """Test that bundled Podman containers are visible."""
        expected = bundled_containers_config['podman']
        if not expected:
            pytest.skip("No Podman containers in bundle packages or BUNDLED_CONTAINERS")

        # Check if podman is available
        output = runqemu_session.run_command('which podman')
        if '/podman' not in output:
            pytest.skip("podman not installed in image")

        # Get podman images
        output = runqemu_session.run_command('podman images', timeout=30)
        print(f"podman images output:\n{output}")

        # Verify each expected container is present
        missing = []
        for container in expected:
            if container not in output:
                missing.append(container)

        assert not missing, f"Missing Podman containers: {missing}\nOutput:\n{output}"

    @pytest.mark.slow
    @pytest.mark.boot
    def test_docker_run_bundled_container(self, runqemu_session, bundled_containers_config):
        """Test that a bundled Docker container can actually run."""
        expected = bundled_containers_config['docker']
        if not expected:
            pytest.skip("No Docker containers configured")

        # Check if docker is available
        output = runqemu_session.run_command('which docker')
        if '/docker' not in output:
            pytest.skip("docker not installed in image")

        # Try to run the first bundled container with a simple command
        # Use --entrypoint to override any image entrypoint, otherwise
        # images with entrypoint like ["sh"] would interpret the command
        # as a script argument rather than executing the binary directly
        container = expected[0]
        output = runqemu_session.run_command(
            f'docker run --rm --entrypoint /bin/echo {container}:latest "CONTAINER_WORKS"',
            timeout=60
        )
        print(f"docker run output:\n{output}")

        assert 'CONTAINER_WORKS' in output, \
            f"Container {container} failed to run.\nOutput:\n{output}"

    @pytest.mark.slow
    @pytest.mark.boot
    def test_podman_run_bundled_container(self, runqemu_session, bundled_containers_config):
        """Test that a bundled Podman container can actually run."""
        expected = bundled_containers_config['podman']
        if not expected:
            pytest.skip("No Podman containers in bundle packages or BUNDLED_CONTAINERS")

        # Check if podman is available
        output = runqemu_session.run_command('which podman')
        if '/podman' not in output:
            pytest.skip("podman not installed in image")

        # Try to run the first bundled container with a simple command
        # Use --entrypoint to override any image entrypoint, otherwise
        # images with entrypoint like ["sh"] would interpret the command
        # as a script argument rather than executing the binary directly
        container = expected[0]
        output = runqemu_session.run_command(
            f'podman run --rm --entrypoint /bin/echo {container}:latest "CONTAINER_WORKS"',
            timeout=60
        )
        print(f"podman run output:\n{output}")

        assert 'CONTAINER_WORKS' in output, \
            f"Container {container} failed to run.\nOutput:\n{output}"


# ============================================================================
# Custom Service File Tests
# ============================================================================

class TestCustomServiceFileSupport:
    """
    Test CONTAINER_SERVICE_FILE varflag support.

    This tests the ability to provide custom systemd service files or
    Podman Quadlet files instead of auto-generated ones.
    """

    def test_bbclass_has_service_file_support(self, meta_virt_dir):
        """Test that the bbclass includes CONTAINER_SERVICE_FILE support."""
        class_file = meta_virt_dir / "classes" / "container-cross-install.bbclass"
        content = class_file.read_text()

        # Check for the key implementation elements
        assert "CONTAINER_SERVICE_FILE" in content, \
            "CONTAINER_SERVICE_FILE variable not found in bbclass"
        assert "get_container_service_file_map" in content, \
            "get_container_service_file_map function not found"
        assert "CONTAINER_SERVICE_FILE_MAP" in content, \
            "CONTAINER_SERVICE_FILE_MAP variable not found"
        assert "install_custom_service" in content, \
            "install_custom_service function not found"

    def test_bundle_class_has_service_file_support(self, meta_virt_dir):
        """Test that container-bundle.bbclass includes CONTAINER_SERVICE_FILE support."""
        class_file = meta_virt_dir / "classes" / "container-bundle.bbclass"
        content = class_file.read_text()

        # Check for the key implementation elements
        assert "CONTAINER_SERVICE_FILE" in content, \
            "CONTAINER_SERVICE_FILE variable not found in container-bundle.bbclass"
        assert "_CONTAINER_SERVICE_FILE_MAP" in content, \
            "_CONTAINER_SERVICE_FILE_MAP variable not found"
        assert "services" in content, \
            "services directory handling not found"

    def test_service_file_map_syntax(self, meta_virt_dir):
        """Test that the service file map function has correct syntax."""
        class_file = meta_virt_dir / "classes" / "container-cross-install.bbclass"
        content = class_file.read_text()

        # Check the function signature and key logic
        assert "def get_container_service_file_map(d):" in content, \
            "get_container_service_file_map function signature not found"
        assert "getVarFlag('CONTAINER_SERVICE_FILE'" in content, \
            "getVarFlag call for CONTAINER_SERVICE_FILE not found"
        assert 'mappings.append' in content or 'mappings =' in content, \
            "Service file mapping logic not found"

    def test_install_custom_service_function(self, meta_virt_dir):
        """Test that install_custom_service handles both Docker and Podman."""
        class_file = meta_virt_dir / "classes" / "container-cross-install.bbclass"
        content = class_file.read_text()

        # Check the function handles both runtimes
        assert 'install_custom_service()' in content or 'install_custom_service ' in content, \
            "install_custom_service function not found"

        # Docker service installation
        assert '/lib/systemd/system' in content, \
            "Docker service directory path not found"
        assert 'multi-user.target.wants' in content, \
            "Systemd enable symlink path not found"

        # Podman Quadlet installation
        assert '/etc/containers/systemd' in content, \
            "Podman Quadlet directory path not found"


class TestCustomServiceFileBoot:
    """
    Boot tests for custom service files.

    These tests verify that custom service files are properly installed
    and enabled in the booted system.
    """

    @pytest.mark.slow
    @pytest.mark.boot
    def test_systemd_services_directory_exists(self, runqemu_session):
        """Test that systemd service directories exist."""
        output = runqemu_session.run_command('ls -la /lib/systemd/system/ | head -5')
        assert 'systemd' in output or 'total' in output, \
            "Systemd system directory not accessible"

    @pytest.mark.slow
    @pytest.mark.boot
    def test_container_services_present(self, runqemu_session, bundled_containers_config):
        """Test that container service files are present (custom or generated)."""
        docker_containers = bundled_containers_config.get('docker', [])

        if not docker_containers:
            pytest.skip("No Docker containers configured")

        # Check if docker is available
        output = runqemu_session.run_command('which docker')
        if '/docker' not in output:
            pytest.skip("docker not installed in image")

        # Check for container service files
        output = runqemu_session.run_command('ls /lib/systemd/system/container-*.service 2>/dev/null || echo "NONE"')

        if 'NONE' in output:
            # No autostart services - check if any containers have autostart
            pytest.skip("No container autostart services found (containers may not have autostart enabled)")

        # Verify at least one service file exists
        assert '.service' in output, \
            f"No container service files found. Output: {output}"

    @pytest.mark.slow
    @pytest.mark.boot
    def test_container_service_enabled(self, runqemu_session, bundled_containers_config):
        """Test that container services are enabled (linked in wants directory)."""
        docker_containers = bundled_containers_config.get('docker', [])

        if not docker_containers:
            pytest.skip("No Docker containers configured")

        # Check for enabled services in multi-user.target.wants
        output = runqemu_session.run_command(
            'ls /etc/systemd/system/multi-user.target.wants/container-*.service 2>/dev/null || echo "NONE"'
        )

        if 'NONE' in output:
            pytest.skip("No container autostart services enabled")

        # Verify services are symlinked
        assert '.service' in output, \
            f"No enabled container services found. Output: {output}"

    @pytest.mark.slow
    @pytest.mark.boot
    def test_custom_service_content(self, runqemu_session, bundled_containers_config):
        """Test that custom service files have expected content markers."""
        docker_containers = bundled_containers_config.get('docker', [])

        if not docker_containers:
            pytest.skip("No Docker containers configured")

        # Find a container service file
        output = runqemu_session.run_command(
            'ls /lib/systemd/system/container-*.service 2>/dev/null | head -1'
        )

        if not output or 'container-' not in output:
            pytest.skip("No container service files found")

        service_file = output.strip().split('\n')[0]

        # Read the service file content
        content = runqemu_session.run_command(f'cat {service_file}')

        # Verify it has expected systemd service structure
        assert '[Unit]' in content, f"Service file missing [Unit] section: {service_file}"
        assert '[Service]' in content, f"Service file missing [Service] section: {service_file}"
        assert '[Install]' in content, f"Service file missing [Install] section: {service_file}"

        # Check for docker-related content
        assert 'docker' in content.lower(), \
            f"Service file doesn't reference docker: {content}"

    @pytest.mark.slow
    @pytest.mark.boot
    def test_podman_quadlet_directory(self, runqemu_session, bundled_containers_config):
        """Test Podman Quadlet directory exists for Podman containers."""
        podman_containers = bundled_containers_config.get('podman', [])

        if not podman_containers:
            pytest.skip("No Podman containers configured")

        # Check if podman is available
        output = runqemu_session.run_command('which podman')
        if '/podman' not in output:
            pytest.skip("podman not installed in image")

        # Check for Quadlet directory
        output = runqemu_session.run_command('ls -la /etc/containers/systemd/ 2>/dev/null || echo "NONE"')

        if 'NONE' in output:
            pytest.skip("Quadlet directory not found (containers may not have autostart enabled)")

        # Check for .container files
        output = runqemu_session.run_command('ls /etc/containers/systemd/*.container 2>/dev/null || echo "NONE"')

        if 'NONE' not in output:
            assert '.container' in output, \
                f"No Quadlet container files found. Output: {output}"
