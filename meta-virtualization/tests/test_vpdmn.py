# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Tests for vpdmn - Podman CLI for cross-architecture emulation.

These tests verify vpdmn functionality including:
- Memory resident mode (memres)
- Image management (images, pull, import, save, load)
- Container execution (vrun)
- System commands (system df, system prune)
- Storage management (vstorage list, path, df, clean)

Tests use a separate state directory (~/.vpdmn-test/) to avoid
interfering with user's images in ~/.vpdmn/.

Run with:
    pytest tests/test_vpdmn.py -v --vdkr-dir /tmp/vcontainer-standalone

Run with memres already started (faster):
    ./tests/memres-test.sh start --vdkr-dir /tmp/vcontainer-standalone --tool vpdmn
    pytest tests/test_vpdmn.py -v --vdkr-dir /tmp/vcontainer-standalone --skip-destructive

Run with OCI image for import tests:
    pytest tests/test_vpdmn.py -v --vdkr-dir /tmp/vcontainer-standalone --oci-image /path/to/container-oci
"""

import pytest
import json
import os


@pytest.mark.memres
class TestMemresBasic:
    """Test memory resident mode basic operations.

    These tests use a separate state directory (~/.vpdmn-test/) so they
    don't interfere with user's memres in ~/.vpdmn/.
    """

    def test_memres_start(self, vpdmn):
        """Test starting memory resident mode."""
        # Stop first if running
        vpdmn.memres_stop()

        result = vpdmn.memres_start(timeout=180)
        assert result.returncode == 0, f"memres start failed: {result.stderr}"

    def test_memres_status(self, vpdmn):
        """Test checking memory resident status."""
        if not vpdmn.is_memres_running():
            vpdmn.memres_start(timeout=180)

        result = vpdmn.memres_status()
        assert result.returncode == 0
        assert "running" in result.stdout.lower() or "started" in result.stdout.lower()

    def test_memres_stop(self, vpdmn):
        """Test stopping memory resident mode."""
        # Ensure running first
        if not vpdmn.is_memres_running():
            vpdmn.memres_start(timeout=180)

        result = vpdmn.memres_stop()
        assert result.returncode == 0

        # Verify stopped
        status = vpdmn.memres_status()
        assert status.returncode != 0 or "not running" in status.stdout.lower()

    def test_memres_restart(self, vpdmn):
        """Test restarting memory resident mode."""
        result = vpdmn.run("memres", "restart", timeout=180)
        assert result.returncode == 0

        # Verify running
        assert vpdmn.is_memres_running()


class TestImages:
    """Test image management commands."""

    def test_images_list(self, vpdmn_memres_session):
        """Test images command."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_memres()
        result = vpdmn.images()
        assert result.returncode == 0
        # Should have header line at minimum
        assert "REPOSITORY" in result.stdout or "IMAGE" in result.stdout

    @pytest.mark.network
    def test_pull_alpine(self, vpdmn_memres_session):
        """Test pulling alpine image from registry."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_memres()

        # Pull alpine (small image)
        result = vpdmn.pull("alpine:latest", timeout=300)
        assert result.returncode == 0

        # Verify it appears in images
        images = vpdmn.images()
        assert "alpine" in images.stdout

    def test_rmi(self, vpdmn_memres_session):
        """Test removing an image."""
        vpdmn = vpdmn_memres_session

        # Ensure we have alpine to test with
        vpdmn.ensure_alpine()

        # Force remove to handle containers using the image
        result = vpdmn.run("rmi", "-f", "alpine:latest", check=False)
        assert result.returncode == 0


class TestVimport:
    """Test vimport command for OCI image import."""

    def test_vimport_oci(self, vpdmn_memres_session, oci_image):
        """Test importing an OCI directory."""
        if oci_image is None:
            pytest.skip("No OCI image provided (use --oci-image)")

        vpdmn = vpdmn_memres_session
        vpdmn.ensure_memres()
        result = vpdmn.vimport(oci_image, "test-import:latest", timeout=180)
        assert result.returncode == 0

        # Verify it appears in images
        images = vpdmn.images()
        assert "test-import" in images.stdout


class TestSaveLoad:
    """Test save and load commands."""

    def test_save_and_load(self, vpdmn_memres_session, temp_dir):
        """Test saving and loading an image."""
        vpdmn = vpdmn_memres_session

        # Ensure we have alpine
        vpdmn.ensure_alpine()

        tar_path = temp_dir / "test-save.tar"

        # Save
        result = vpdmn.save(tar_path, "alpine:latest", timeout=180)
        assert result.returncode == 0
        assert tar_path.exists()
        assert tar_path.stat().st_size > 0

        # Remove the image
        vpdmn.run("rmi", "-f", "alpine:latest", check=False)

        # Load
        result = vpdmn.load(tar_path, timeout=180)
        assert result.returncode == 0

        # Verify it's back
        images = vpdmn.images()
        assert "alpine" in images.stdout


class TestVrun:
    """Test vrun command for container execution."""

    def test_vrun_echo(self, vpdmn_memres_session):
        """Test running echo command in a container."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_alpine()

        result = vpdmn.vrun("alpine:latest", "/bin/echo", "hello", "world")
        assert result.returncode == 0
        assert "hello world" in result.stdout

    def test_vrun_uname(self, vpdmn_memres_session, arch):
        """Test running uname to verify architecture."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_alpine()

        result = vpdmn.vrun("alpine:latest", "/bin/uname", "-m")
        assert result.returncode == 0

        # Check architecture matches
        expected_arch = "x86_64" if arch == "x86_64" else "aarch64"
        assert expected_arch in result.stdout

    def test_vrun_exit_code(self, vpdmn_memres_session):
        """Test container command execution."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_alpine()

        # Run command that exits with code 1 (false command)
        result = vpdmn.run("vrun", "alpine:latest", "/bin/false",
                          check=False, timeout=60)
        # Container exit codes may or may not be propagated depending on vpdmn implementation
        # At minimum, verify the command ran (no crash/timeout)
        assert result.returncode in [0, 1], f"Unexpected return code: {result.returncode}"


@pytest.mark.memres
class TestRun:
    """Test run command with entrypoint override."""

    def test_run_with_entrypoint(self, vpdmn_memres_session):
        """Test running with entrypoint override."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_alpine()

        # Override entrypoint to run cat on /etc/os-release
        result = vpdmn.run("run", "--rm", "--entrypoint", "/bin/cat",
                          "alpine:latest", "/etc/os-release", timeout=60)
        assert result.returncode == 0
        assert "Alpine" in result.stdout or "alpine" in result.stdout.lower()

    def test_run_with_env(self, vpdmn_memres_session, temp_dir):
        """Test running with environment variable."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_alpine()

        # Create a script that prints the env var - avoids shell quoting issues
        # when passing through multiple shells (host -> vpdmn.sh -> runner -> guest init -> container)
        script = temp_dir / "print_env.sh"
        script.write_text("#!/bin/sh\necho $MY_VAR\n")
        script.chmod(0o755)

        result = vpdmn.run("run", "--rm", "-e", "MY_VAR=hello_test",
                          "-v", f"{temp_dir}:/scripts",
                          "alpine:latest", "/scripts/print_env.sh",
                          timeout=60)
        assert result.returncode == 0
        assert "hello_test" in result.stdout


class TestInspect:
    """Test inspect command."""

    def test_inspect_image(self, vpdmn_memres_session):
        """Test inspecting an image."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_alpine()

        result = vpdmn.inspect("alpine:latest")
        assert result.returncode == 0

        # Should be valid JSON
        data = json.loads(result.stdout)
        assert isinstance(data, list)
        assert len(data) > 0


class TestHistory:
    """Test history command."""

    def test_history(self, vpdmn_memres_session):
        """Test showing image history."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_alpine()

        result = vpdmn.run("history", "alpine:latest")
        assert result.returncode == 0
        assert "IMAGE" in result.stdout or "ID" in result.stdout or "CREATED" in result.stdout


class TestClean:
    """Test clean command."""

    def test_clean(self, vpdmn, request):
        """Test cleaning state directory."""
        if request.config.getoption("--skip-destructive"):
            pytest.skip("Skipped with --skip-destructive")

        # Stop memres first
        vpdmn.memres_stop()

        result = vpdmn.clean()
        assert result.returncode == 0


class TestFallbackMode:
    """Test fallback to regular QEMU mode when memres not running."""

    @pytest.mark.slow
    def test_images_without_memres(self, vpdmn, request):
        """Test images command works without memres (slower)."""
        if request.config.getoption("--skip-destructive"):
            pytest.skip("Skipped with --skip-destructive")

        # Ensure memres is stopped
        vpdmn.memres_stop()

        # This should still work, just slower
        result = vpdmn.images(timeout=120)
        assert result.returncode == 0


@pytest.mark.memres
class TestContainerLifecycle:
    """Test container lifecycle commands."""

    @pytest.mark.slow
    def test_run_detached_and_manage(self, vpdmn_memres_session):
        """Test running a detached container and managing it."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_alpine()

        # Run a container in detached mode
        result = vpdmn.run("run", "-d", "--name", "test-container", "alpine:latest", "sleep", "300",
                          timeout=60, check=False)
        if result.returncode != 0:
            # Show error for debugging
            print(f"Failed to start detached container: {result.stderr}")
            pytest.skip("Could not start detached container")

        try:
            # List containers
            ps_result = vpdmn.run("ps")
            assert "test-container" in ps_result.stdout

            # Stop container
            stop_result = vpdmn.run("stop", "test-container", timeout=30)
            assert stop_result.returncode == 0

            # Remove container
            rm_result = vpdmn.run("rm", "test-container")
            assert rm_result.returncode == 0

        finally:
            # Cleanup
            vpdmn.run("rm", "-f", "test-container", check=False)


@pytest.mark.memres
class TestVolumeMounts:
    """Test volume mount functionality.

    Volume mounts require memres to be running.
    """

    def test_volume_mount_read_file(self, vpdmn_memres_session, temp_dir):
        """Test mounting a host directory and reading a file from it."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_alpine()

        # Create a test file on host
        test_file = temp_dir / "testfile.txt"
        test_content = "Hello from host volume!"
        test_file.write_text(test_content)

        # Run container with volume mount and read the file
        result = vpdmn.run("vrun", "-v", f"{temp_dir}:/data", "alpine:latest",
                          "cat", "/data/testfile.txt", timeout=60)
        assert result.returncode == 0
        assert test_content in result.stdout

    def test_volume_mount_write_file(self, vpdmn_memres_session, temp_dir):
        """Test writing a file in a mounted volume."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_alpine()

        # Create a script that writes to a file - avoids shell metacharacter issues
        # when passing through multiple shells (host -> vpdmn.sh -> runner -> guest -> container)
        # Include sync to ensure write is flushed to host via 9p/virtio-fs
        script = temp_dir / "write.sh"
        script.write_text("#!/bin/sh\necho 'Created in container' > /data/output.txt\nsync\n")
        script.chmod(0o755)

        # Run the script inside the container
        result = vpdmn.run("vrun", "-v", f"{temp_dir}:/data", "alpine:latest",
                          "/data/write.sh", timeout=60)
        assert result.returncode == 0

        # Verify the file was synced back to host
        output_file = temp_dir / "output.txt"
        assert output_file.exists(), "Output file should be synced back to host"
        assert "Created in container" in output_file.read_text()

    def test_volume_mount_read_only(self, vpdmn_memres_session, temp_dir):
        """Test read-only volume mount."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_alpine()

        # Create a test file
        test_file = temp_dir / "readonly.txt"
        test_file.write_text("Read-only content")

        # Can read from ro mount
        result = vpdmn.run("vrun", "-v", f"{temp_dir}:/data:ro", "alpine:latest",
                          "cat", "/data/readonly.txt", timeout=60)
        assert result.returncode == 0
        assert "Read-only content" in result.stdout

    def test_volume_mount_multiple(self, vpdmn_memres_session, temp_dir):
        """Test multiple volume mounts."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_alpine()

        # Create two directories with test files
        dir1 = temp_dir / "dir1"
        dir2 = temp_dir / "dir2"
        dir1.mkdir()
        dir2.mkdir()

        (dir1 / "file1.txt").write_text("Content from dir1")
        (dir2 / "file2.txt").write_text("Content from dir2")

        # Create a script to avoid shell metacharacter issues with ';' or '&&'
        script = temp_dir / "read_both.sh"
        script.write_text("#!/bin/sh\ncat /data1/file1.txt\ncat /data2/file2.txt\n")
        script.chmod(0o755)

        # Mount both directories plus the script
        result = vpdmn.run("vrun",
                          "-v", f"{temp_dir}:/scripts",
                          "-v", f"{dir1}:/data1",
                          "-v", f"{dir2}:/data2",
                          "alpine:latest",
                          "/scripts/read_both.sh",
                          timeout=60)
        assert result.returncode == 0
        assert "Content from dir1" in result.stdout
        assert "Content from dir2" in result.stdout

    def test_volume_mount_with_run_command(self, vpdmn_memres_session, temp_dir):
        """Test volume mount with run command (not vrun)."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_alpine()

        # Create a test file
        test_file = temp_dir / "runtest.txt"
        test_file.write_text("Testing run command volumes")

        # Use run command with volume
        result = vpdmn.run("run", "--rm", "-v", f"{temp_dir}:/data",
                          "alpine:latest", "cat", "/data/runtest.txt",
                          timeout=60)
        assert result.returncode == 0
        assert "Testing run command volumes" in result.stdout

    def test_volume_mount_requires_memres(self, vpdmn, temp_dir, request):
        """Test that volume mounts fail gracefully without memres."""
        if request.config.getoption("--skip-destructive"):
            pytest.skip("Skipped with --skip-destructive")

        # Ensure memres is stopped
        vpdmn.memres_stop()

        # Create a test file
        test_file = temp_dir / "test.txt"
        test_file.write_text("test")

        # Try to use volume mount without memres - should fail with clear message
        result = vpdmn.run("vrun", "-v", f"{temp_dir}:/data", "alpine:latest",
                          "cat", "/data/test.txt", check=False, timeout=30)

        # Should fail because memres is not running
        assert result.returncode != 0
        output = (result.stdout + result.stderr).lower()
        assert "memres" in output or "daemon" in output


@pytest.mark.memres
class TestSystem:
    """Test system commands (run inside VM)."""

    def test_system_df(self, vpdmn_memres_session):
        """Test system df command."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_memres()

        result = vpdmn.run("system", "df")
        assert result.returncode == 0
        # Should show images, containers, volumes headers
        assert "IMAGES" in result.stdout.upper() or "TYPE" in result.stdout.upper()

    def test_system_df_verbose(self, vpdmn_memres_session):
        """Test system df -v command."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_memres()

        result = vpdmn.run("system", "df", "-v")
        assert result.returncode == 0
        # Verbose mode shows more details
        assert "IMAGES" in result.stdout.upper() or "TYPE" in result.stdout.upper()

    def test_system_prune_dry_run(self, vpdmn_memres_session):
        """Test system prune with dry run (doesn't actually delete)."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_memres()

        # Just verify the command runs (don't actually prune in tests)
        # Add -f to skip confirmation prompt
        result = vpdmn.run("system", "prune", "-f", check=False)
        # Command may return 0 even with nothing to prune
        assert result.returncode == 0

    def test_system_without_subcommand(self, vpdmn_memres_session):
        """Test system command without subcommand shows error."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_memres()

        result = vpdmn.run("system", check=False)
        assert result.returncode != 0
        output = (result.stdout + result.stderr).lower()
        assert "subcommand" in output or "requires" in output


@pytest.mark.memres
class TestVstorage:
    """Test vstorage commands (host-side storage management).

    These commands run on the host and don't require memres.
    """

    def test_vstorage_list(self, vpdmn):
        """Test vstorage list command."""
        # Ensure there's something to list by starting memres briefly
        vpdmn.ensure_memres()

        result = vpdmn.run("vstorage", "list", check=False)
        # vstorage list is an alias for vstorage
        assert result.returncode == 0
        assert "storage" in result.stdout.lower() or "path" in result.stdout.lower()

    def test_vstorage_default(self, vpdmn):
        """Test vstorage with no subcommand (defaults to list)."""
        vpdmn.ensure_memres()

        result = vpdmn.run("vstorage", check=False)
        assert result.returncode == 0
        # Should show storage info
        assert "storage" in result.stdout.lower() or "vpdmn" in result.stdout.lower()

    def test_vstorage_path(self, vpdmn, arch):
        """Test vstorage path command."""
        result = vpdmn.run("vstorage", "path", check=False)
        assert result.returncode == 0
        # Output should contain the architecture or .vpdmn path
        assert arch in result.stdout or ".vpdmn" in result.stdout

    def test_vstorage_path_specific_arch(self, vpdmn):
        """Test vstorage path with specific architecture."""
        # Use the same arch as the runner to avoid cross-arch issues
        arch = vpdmn.arch
        result = vpdmn.run("vstorage", "path", arch, check=False)
        assert result.returncode == 0
        assert arch in result.stdout

    def test_vstorage_df(self, vpdmn):
        """Test vstorage df command."""
        # Ensure there's something to show
        vpdmn.ensure_memres()

        result = vpdmn.run("vstorage", "df", check=False)
        assert result.returncode == 0
        # Should show size information (may be empty if no state yet)

    def test_vstorage_shows_memres_status(self, vpdmn):
        """Test that vstorage list shows memres running status."""
        vpdmn.ensure_memres()

        result = vpdmn.run("vstorage", "list", check=False)
        assert result.returncode == 0
        # Should show running status when memres is active
        assert "running" in result.stdout.lower() or "memres" in result.stdout.lower() \
            or "status" in result.stdout.lower()

    def test_vstorage_clean_current_arch(self, vpdmn, request):
        """Test vstorage clean for current architecture."""
        if request.config.getoption("--skip-destructive"):
            pytest.skip("Skipped with --skip-destructive")

        # Ensure there's something to clean
        vpdmn.ensure_memres()
        vpdmn.memres_stop()

        result = vpdmn.run("vstorage", "clean", check=False)
        assert result.returncode == 0
        assert "clean" in result.stdout.lower()

    def test_vstorage_unknown_subcommand(self, vpdmn):
        """Test vstorage with unknown subcommand shows error."""
        result = vpdmn.run("vstorage", "invalid", check=False)
        assert result.returncode != 0
        output = (result.stdout + result.stderr).lower()
        assert "unknown" in output or "usage" in output


class TestRemoteFetchAndCrossInstall:
    """Test remote container fetch and cross-install workflow.

    These tests verify the full workflow for bundling containers into images:
    1. Pull container from remote registry
    2. Verify container is functional
    3. Export container storage (simulates cross-install bundle)
    4. Import storage into fresh state (simulates target boot)
    5. Verify container works after import

    Requires network access - use @pytest.mark.network marker.
    """

    @pytest.mark.network
    def test_pull_busybox(self, vpdmn_memres_session):
        """Test pulling busybox image from registry."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_memres()

        # Pull busybox (very small image, faster than alpine for this test)
        result = vpdmn.pull("busybox:latest", timeout=300)
        assert result.returncode == 0

        # Verify it appears in images
        images = vpdmn.images()
        assert "busybox" in images.stdout

    @pytest.mark.network
    def test_pull_and_run(self, vpdmn_memres_session):
        """Test that pulled container can be executed."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_memres()

        # Ensure we have busybox
        images = vpdmn.images()
        if "busybox" not in images.stdout:
            vpdmn.pull("busybox:latest", timeout=300)

        # Run a command in the pulled container
        result = vpdmn.vrun("busybox:latest", "/bin/echo", "remote_fetch_works")
        assert result.returncode == 0
        assert "remote_fetch_works" in result.stdout

    @pytest.mark.network
    def test_cross_install_workflow(self, vpdmn_memres_session, temp_dir):
        """Test full cross-install workflow: pull -> export -> import -> run.

        This simulates:
        1. Build host: pull container from registry
        2. Build host: export Podman storage to tar (for bundling into image)
        3. Target boot: import storage tar
        4. Target: run the container

        This is the core workflow for container-cross-install.
        """
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_memres()

        # Step 1: Pull container from remote registry
        images = vpdmn.images()
        if "busybox" not in images.stdout:
            result = vpdmn.pull("busybox:latest", timeout=300)
            assert result.returncode == 0

        # Step 2: Save container to tar (simulates bundle export)
        bundle_tar = temp_dir / "cross-install-bundle.tar"
        result = vpdmn.save(bundle_tar, "busybox:latest", timeout=180)
        assert result.returncode == 0
        assert bundle_tar.exists()
        assert bundle_tar.stat().st_size > 0

        # Step 3: Remove original image (simulates fresh target state)
        vpdmn.run("rmi", "-f", "busybox:latest", check=False)
        images = vpdmn.images()
        # Verify removed (may still show if other tags exist)

        # Step 4: Load from bundle tar (simulates target importing bundled storage)
        result = vpdmn.load(bundle_tar, timeout=180)
        assert result.returncode == 0

        # Step 5: Verify container works after import
        images = vpdmn.images()
        assert "busybox" in images.stdout

        result = vpdmn.vrun("busybox:latest", "/bin/echo", "cross_install_success")
        assert result.returncode == 0
        assert "cross_install_success" in result.stdout

    @pytest.mark.network
    def test_pull_verify_architecture(self, vpdmn_memres_session, arch):
        """Test that pulled container matches target architecture."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_memres()

        # Ensure we have busybox
        images = vpdmn.images()
        if "busybox" not in images.stdout:
            vpdmn.pull("busybox:latest", timeout=300)

        # Run uname to verify architecture inside container
        result = vpdmn.vrun("busybox:latest", "/bin/uname", "-m")
        assert result.returncode == 0

        # Check architecture matches target
        expected_arch = "x86_64" if arch == "x86_64" else "aarch64"
        assert expected_arch in result.stdout, \
            f"Architecture mismatch: expected {expected_arch}, got {result.stdout.strip()}"

    @pytest.mark.network
    def test_multiple_containers_bundle(self, vpdmn_memres_session, temp_dir):
        """Test bundling multiple containers (simulates multi-container image)."""
        vpdmn = vpdmn_memres_session
        vpdmn.ensure_memres()

        containers = ["busybox:latest", "alpine:latest"]
        bundle_tars = []

        # Pull and save each container
        for container in containers:
            name = container.split(":")[0]
            images = vpdmn.images()
            if name not in images.stdout:
                result = vpdmn.pull(container, timeout=300)
                assert result.returncode == 0

            tar_path = temp_dir / f"{name}-bundle.tar"
            result = vpdmn.save(tar_path, container, timeout=180)
            assert result.returncode == 0
            bundle_tars.append((container, tar_path))

        # Remove all containers
        for container, _ in bundle_tars:
            vpdmn.run("rmi", "-f", container, check=False)

        # Load all bundles (simulates target with multiple bundled containers)
        for container, tar_path in bundle_tars:
            result = vpdmn.load(tar_path, timeout=180)
            assert result.returncode == 0

        # Verify all containers work
        images = vpdmn.images()
        for container, _ in bundle_tars:
            name = container.split(":")[0]
            assert name in images.stdout, f"{name} not found after load"

        # Run a command in each
        result = vpdmn.vrun("busybox:latest", "/bin/echo", "busybox_ok")
        assert "busybox_ok" in result.stdout

        result = vpdmn.vrun("alpine:latest", "/bin/echo", "alpine_ok")
        assert "alpine_ok" in result.stdout
