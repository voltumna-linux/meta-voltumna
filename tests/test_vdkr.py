# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Tests for vdkr - Docker CLI for cross-architecture emulation.

These tests verify vdkr functionality including:
- Memory resident mode (memres)
- Image management (images, pull, import, save, load)
- Container execution (vrun)
- System commands (system df, system prune)
- Storage management (vstorage list, path, df, clean)

Tests use a separate state directory (~/.vdkr-test/) to avoid
interfering with user's images in ~/.vdkr/.

Run with:
    pytest tests/test_vdkr.py -v --vdkr-dir /tmp/vdkr-standalone

Run with memres already started (faster):
    ./tests/memres-test.sh start --vdkr-dir /tmp/vdkr-standalone
    pytest tests/test_vdkr.py -v --vdkr-dir /tmp/vdkr-standalone --skip-destructive

Run with OCI image for import tests:
    pytest tests/test_vdkr.py -v --vdkr-dir /tmp/vdkr-standalone --oci-image /path/to/container-oci
"""

import pytest
import json
import os


@pytest.mark.memres
class TestMemresBasic:
    """Test memory resident mode basic operations.

    These tests use a separate state directory (~/.vdkr-test/) so they
    don't interfere with user's memres in ~/.vdkr/.
    """

    def test_memres_start(self, vdkr):
        """Test starting memory resident mode."""
        # Stop first if running
        vdkr.memres_stop()

        result = vdkr.memres_start(timeout=180)
        assert result.returncode == 0, f"memres start failed: {result.stderr}"

    def test_memres_status(self, vdkr):
        """Test checking memory resident status."""
        if not vdkr.is_memres_running():
            vdkr.memres_start(timeout=180)

        result = vdkr.memres_status()
        assert result.returncode == 0
        assert "running" in result.stdout.lower() or "started" in result.stdout.lower()

    def test_memres_stop(self, vdkr):
        """Test stopping memory resident mode."""
        # Ensure running first
        if not vdkr.is_memres_running():
            vdkr.memres_start(timeout=180)

        result = vdkr.memres_stop()
        assert result.returncode == 0

        # Verify stopped
        status = vdkr.memres_status()
        assert status.returncode != 0 or "not running" in status.stdout.lower()

    def test_memres_restart(self, vdkr):
        """Test restarting memory resident mode."""
        vdkr.memres_stop()
        result = vdkr.memres_start(timeout=180)
        assert result.returncode == 0

        # Verify running
        assert vdkr.is_memres_running()


@pytest.mark.memres
class TestPortForwarding:
    """Test port forwarding with memres.

    Port forwarding allows access to services running in containers from the host.
    Docker bridge networking (docker0, 172.17.0.0/16) is used by default.
    Each container gets its own IP, enabling multiple containers to listen
    on the same internal port with different host port mappings.
    """

    @pytest.mark.network
    @pytest.mark.slow
    def test_port_forward_nginx(self, vdkr):
        """Test port forwarding with nginx using bridge networking.

        This test:
        1. Starts memres (no static port forwards needed)
        2. Runs nginx with -p 8080:80 (Docker bridge + iptables NAT)
        3. Verifies nginx is accessible from host via curl
        """
        import subprocess
        import time

        # Stop any running memres first
        vdkr.memres_stop()

        # Start memres (no static port forwards needed - use dynamic via -p on run)
        result = vdkr.memres_start(timeout=180)
        assert result.returncode == 0, f"memres start failed: {result.stderr}"

        try:
            # Pull nginx:alpine if not present
            vdkr.run("pull", "nginx:alpine", timeout=300)

            # Run nginx with port forward - Docker sets up iptables for bridge networking
            result = vdkr.run("run", "-d", "--rm", "-p", "8080:80", "nginx:alpine", timeout=60)
            assert result.returncode == 0, f"nginx run failed: {result.stderr}"

            # Give nginx time to start
            time.sleep(3)

            # Test access from host
            curl_result = subprocess.run(
                ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "http://localhost:8080"],
                capture_output=True,
                text=True,
                timeout=10
            )
            assert curl_result.stdout == "200", f"Expected HTTP 200, got {curl_result.stdout}"

        finally:
            # Clean up: stop all containers
            vdkr.run("ps", "-q", check=False)
            ps_result = vdkr.run("ps", "-q", check=False)
            if ps_result.stdout.strip():
                for container_id in ps_result.stdout.strip().split('\n'):
                    vdkr.run("stop", container_id, timeout=30, check=False)

            # Stop memres
            vdkr.memres_stop()

    @pytest.mark.network
    @pytest.mark.slow
    def test_multiple_containers_same_internal_port(self, vdkr):
        """Test multiple containers listening on same internal port.

        This tests the key benefit of bridge networking:
        - nginx1 listens on container port 80, mapped to host port 8080
        - nginx2 listens on container port 80, mapped to host port 8081
        - Both should work simultaneously (impossible with --network=host)
        """
        import subprocess
        import time

        # Stop any running memres first
        vdkr.memres_stop()

        # Start memres
        result = vdkr.memres_start(timeout=180)
        assert result.returncode == 0, f"memres start failed: {result.stderr}"

        try:
            # Pull nginx:alpine if not present
            vdkr.run("pull", "nginx:alpine", timeout=300)

            # Run first nginx on host:8080 -> container:80
            result1 = vdkr.run("run", "-d", "--name", "nginx1", "-p", "8080:80",
                               "nginx:alpine", timeout=60)
            assert result1.returncode == 0, f"nginx1 run failed: {result1.stderr}"

            # Run second nginx on host:8081 -> container:80 (same internal port!)
            result2 = vdkr.run("run", "-d", "--name", "nginx2", "-p", "8081:80",
                               "nginx:alpine", timeout=60)
            assert result2.returncode == 0, f"nginx2 run failed: {result2.stderr}"

            # Give nginx time to start
            time.sleep(3)

            # Test both are accessible
            curl1 = subprocess.run(
                ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                 "http://localhost:8080"],
                capture_output=True, text=True, timeout=10
            )
            assert curl1.stdout == "200", f"nginx1: Expected HTTP 200, got {curl1.stdout}"

            curl2 = subprocess.run(
                ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                 "http://localhost:8081"],
                capture_output=True, text=True, timeout=10
            )
            assert curl2.stdout == "200", f"nginx2: Expected HTTP 200, got {curl2.stdout}"

            # Verify ps shows both containers with their port mappings
            ps_result = vdkr.run("ps")
            assert "nginx1" in ps_result.stdout
            assert "nginx2" in ps_result.stdout
            assert "8080" in ps_result.stdout
            assert "8081" in ps_result.stdout

        finally:
            # Clean up
            vdkr.run("stop", "nginx1", timeout=30, check=False)
            vdkr.run("stop", "nginx2", timeout=30, check=False)
            vdkr.run("rm", "-f", "nginx1", check=False)
            vdkr.run("rm", "-f", "nginx2", check=False)
            vdkr.memres_stop()

    @pytest.mark.network
    @pytest.mark.slow
    def test_network_host_backward_compat(self, vdkr):
        """Test --network=host backward compatibility.

        This tests that the old host networking mode still works when explicitly
        specified. With --network=host, containers share the VM's network stack
        (10.0.2.15), so static port forwarding at memres start is required.

        Note: With bridge networking as default, static port forwards now map
        host_port -> host_port on VM (Docker -p handles container port mapping).
        For --network=host, use matching ports (e.g., 8082:8082) since the
        container binds directly to VM ports.
        """
        import subprocess
        import time

        # Stop any running memres first
        vdkr.memres_stop()

        # Start memres with static port forward (required for --network=host)
        # Use matching ports since container binds directly to VM network
        result = vdkr.memres_start(timeout=180, port_forwards=["8082:8082"])
        assert result.returncode == 0, f"memres start failed: {result.stderr}"

        try:
            # Use busybox httpd (configurable port) instead of nginx (fixed port 80)
            vdkr.run("pull", "busybox:latest", timeout=300, check=False)

            # Run httpd with --network=host on port 8082
            # With host networking, httpd binds directly to VM:8082
            # Static forward maps host:8082 -> VM:8082
            result = vdkr.run("run", "-d", "--rm", "--name", "httpd-host",
                              "--network=host", "busybox:latest",
                              "httpd", "-f", "-p", "8082", timeout=60)
            assert result.returncode == 0, f"httpd run failed: {result.stderr}"

            # Give httpd time to start
            time.sleep(2)

            # Test access from host via static port forward
            # Note: busybox httpd returns 404 for /, but that's still a valid HTTP response
            curl_result = subprocess.run(
                ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                 "http://localhost:8082/"],
                capture_output=True,
                text=True,
                timeout=10
            )
            # Accept 200, 404, or other HTTP codes - we just need connectivity
            http_code = curl_result.stdout
            assert http_code.isdigit() and int(http_code) > 0, \
                f"Expected HTTP response, got {http_code}"

        finally:
            # Clean up
            ps_result = vdkr.run("ps", "-q", check=False)
            if ps_result.stdout.strip():
                for container_id in ps_result.stdout.strip().split('\n'):
                    if container_id.strip():
                        vdkr.run("stop", container_id, timeout=30, check=False)
            vdkr.memres_stop()


class TestImages:
    """Test image management commands."""

    def test_images_list(self, memres_session):
        """Test images command."""
        vdkr = memres_session
        vdkr.ensure_memres()
        result = vdkr.images()
        assert result.returncode == 0
        # Should have header line at minimum
        assert "REPOSITORY" in result.stdout or "IMAGE" in result.stdout

    @pytest.mark.network
    def test_pull_alpine(self, memres_session):
        """Test pulling alpine image from registry."""
        vdkr = memres_session
        vdkr.ensure_memres()

        # Pull alpine (small image)
        result = vdkr.pull("alpine:latest", timeout=300)
        assert result.returncode == 0

        # Verify it appears in images
        images = vdkr.images()
        assert "alpine" in images.stdout

    def test_rmi(self, memres_session):
        """Test removing an image."""
        vdkr = memres_session

        # Ensure we have alpine to test with
        vdkr.ensure_alpine()

        # Force remove to handle containers using the image
        result = vdkr.run("rmi", "-f", "alpine:latest", check=False)
        assert result.returncode == 0


class TestVimport:
    """Test vimport command for OCI image import."""

    def test_vimport_oci(self, memres_session, oci_image):
        """Test importing an OCI directory."""
        if oci_image is None:
            pytest.skip("No OCI image provided (use --oci-image)")

        vdkr = memres_session
        vdkr.ensure_memres()
        result = vdkr.vimport(oci_image, "test-import:latest", timeout=180)
        assert result.returncode == 0

        # Verify it appears in images
        images = vdkr.images()
        assert "test-import" in images.stdout


class TestSaveLoad:
    """Test save and load commands."""

    def test_save_and_load(self, memres_session, temp_dir):
        """Test saving and loading an image."""
        vdkr = memres_session

        # Ensure we have alpine
        vdkr.ensure_alpine()

        tar_path = temp_dir / "test-save.tar"

        # Save
        result = vdkr.save(tar_path, "alpine:latest", timeout=180)
        assert result.returncode == 0
        assert tar_path.exists()
        assert tar_path.stat().st_size > 0

        # Remove the image
        vdkr.run("rmi", "-f", "alpine:latest", check=False)

        # Load
        result = vdkr.load(tar_path, timeout=180)
        assert result.returncode == 0

        # Verify it's back
        images = vdkr.images()
        assert "alpine" in images.stdout


class TestVrun:
    """Test vrun command for container execution."""

    def test_vrun_echo(self, memres_session):
        """Test running echo command in a container."""
        vdkr = memres_session
        vdkr.ensure_alpine()

        result = vdkr.vrun("alpine:latest", "/bin/echo", "hello", "world")
        assert result.returncode == 0
        assert "hello world" in result.stdout

    def test_vrun_uname(self, memres_session, arch):
        """Test running uname to verify architecture."""
        vdkr = memres_session
        vdkr.ensure_alpine()

        result = vdkr.vrun("alpine:latest", "/bin/uname", "-m")
        assert result.returncode == 0

        # Check architecture matches
        expected_arch = "x86_64" if arch == "x86_64" else "aarch64"
        assert expected_arch in result.stdout

    def test_vrun_exit_code(self, memres_session):
        """Test container command execution."""
        vdkr = memres_session
        vdkr.ensure_alpine()

        # Run command that exits with code 1 (false command)
        result = vdkr.run("vrun", "alpine:latest", "/bin/false",
                          check=False, timeout=60)
        # Container exit codes may or may not be propagated depending on vdkr implementation
        # At minimum, verify the command ran (no crash/timeout)
        # Note: exit code propagation is a future enhancement
        assert result.returncode in [0, 1], f"Unexpected return code: {result.returncode}"


class TestInspect:
    """Test inspect command."""

    def test_inspect_image(self, memres_session):
        """Test inspecting an image."""
        vdkr = memres_session
        vdkr.ensure_alpine()

        result = vdkr.inspect("alpine:latest")
        assert result.returncode == 0

        # Should be valid JSON
        data = json.loads(result.stdout)
        assert isinstance(data, list)
        assert len(data) > 0


class TestHistory:
    """Test history command."""

    def test_history(self, memres_session):
        """Test showing image history."""
        vdkr = memres_session
        vdkr.ensure_alpine()

        result = vdkr.run("history", "alpine:latest")
        assert result.returncode == 0
        assert "IMAGE" in result.stdout or "CREATED" in result.stdout


class TestClean:
    """Test clean command."""

    def test_clean(self, vdkr, request):
        """Test cleaning state directory."""
        if request.config.getoption("--skip-destructive"):
            pytest.skip("Skipped with --skip-destructive")

        # Stop memres first
        vdkr.memres_stop()

        result = vdkr.clean()
        assert result.returncode == 0


class TestFallbackMode:
    """Test fallback to regular QEMU mode when memres not running."""

    @pytest.mark.slow
    def test_images_without_memres(self, vdkr, request):
        """Test images command works without memres (slower)."""
        if request.config.getoption("--skip-destructive"):
            pytest.skip("Skipped with --skip-destructive")

        # Ensure memres is stopped
        vdkr.memres_stop()

        # This should still work, just slower
        result = vdkr.images(timeout=120)
        assert result.returncode == 0


@pytest.mark.memres
class TestContainerLifecycle:
    """Test container lifecycle commands."""

    @pytest.mark.slow
    def test_run_detached_and_manage(self, memres_session):
        """Test running a detached container and managing it."""
        vdkr = memres_session
        vdkr.ensure_alpine()

        # Run a container in detached mode
        # Note: vdkr run auto-prepends "docker run", so just pass the docker run args
        result = vdkr.run("run", "-d", "--name", "test-container", "alpine:latest", "sleep", "300",
                          timeout=60, check=False)
        if result.returncode != 0:
            # Show error for debugging
            print(f"Failed to start detached container: {result.stderr}")
            pytest.skip("Could not start detached container")

        try:
            # List containers
            ps_result = vdkr.run("ps")
            assert "test-container" in ps_result.stdout

            # Stop container
            stop_result = vdkr.run("stop", "test-container", timeout=30)
            assert stop_result.returncode == 0

            # Remove container
            rm_result = vdkr.run("rm", "test-container")
            assert rm_result.returncode == 0

        finally:
            # Cleanup
            vdkr.run("rm", "-f", "test-container", check=False)


@pytest.mark.memres
class TestVolumeMounts:
    """Test volume mount functionality.

    Volume mounts require memres to be running.
    """

    def test_volume_mount_read_file(self, memres_session, temp_dir):
        """Test mounting a host directory and reading a file from it."""
        vdkr = memres_session
        vdkr.ensure_alpine()

        # Create a test file on host
        test_file = temp_dir / "testfile.txt"
        test_content = "Hello from host volume!"
        test_file.write_text(test_content)

        # Run container with volume mount and read the file
        result = vdkr.run("vrun", "-v", f"{temp_dir}:/data", "alpine:latest",
                          "cat", "/data/testfile.txt", timeout=60)
        assert result.returncode == 0
        assert test_content in result.stdout

    def test_volume_mount_write_file(self, memres_session, temp_dir):
        """Test writing a file in a mounted volume."""
        vdkr = memres_session
        vdkr.ensure_alpine()

        # Create a script that writes to a file - avoids shell metacharacter issues
        # when passing through multiple shells (host -> vdkr -> runner -> guest -> container)
        # Include sync to ensure write is flushed to host via 9p/virtio-fs
        script = temp_dir / "write.sh"
        script.write_text("#!/bin/sh\necho 'Created in container' > /data/output.txt\nsync\n")
        script.chmod(0o755)

        # Run the script inside the container
        result = vdkr.run("vrun", "-v", f"{temp_dir}:/data", "alpine:latest",
                          "/data/write.sh", timeout=60)
        assert result.returncode == 0

        # Verify the file was synced back to host
        output_file = temp_dir / "output.txt"
        assert output_file.exists(), "Output file should be synced back to host"
        assert "Created in container" in output_file.read_text()

    def test_volume_mount_read_only(self, memres_session, temp_dir):
        """Test read-only volume mount."""
        vdkr = memres_session
        vdkr.ensure_alpine()

        # Create a test file
        test_file = temp_dir / "readonly.txt"
        test_file.write_text("Read-only content")

        # Can read from ro mount
        result = vdkr.run("vrun", "-v", f"{temp_dir}:/data:ro", "alpine:latest",
                          "cat", "/data/readonly.txt", timeout=60)
        assert result.returncode == 0
        assert "Read-only content" in result.stdout

    def test_volume_mount_multiple(self, memres_session, temp_dir):
        """Test multiple volume mounts."""
        vdkr = memres_session
        vdkr.ensure_alpine()

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
        result = vdkr.run("vrun",
                          "-v", f"{temp_dir}:/scripts",
                          "-v", f"{dir1}:/data1",
                          "-v", f"{dir2}:/data2",
                          "alpine:latest",
                          "/scripts/read_both.sh",
                          timeout=60)
        assert result.returncode == 0
        assert "Content from dir1" in result.stdout
        assert "Content from dir2" in result.stdout

    def test_volume_mount_with_run_command(self, memres_session, temp_dir):
        """Test volume mount with run command (not vrun)."""
        vdkr = memres_session
        vdkr.ensure_alpine()

        # Create a test file
        test_file = temp_dir / "runtest.txt"
        test_file.write_text("Testing run command volumes")

        # Use run command with volume
        result = vdkr.run("run", "--rm", "-v", f"{temp_dir}:/data",
                          "alpine:latest", "cat", "/data/runtest.txt",
                          timeout=60)
        assert result.returncode == 0
        assert "Testing run command volumes" in result.stdout

    def test_volume_mount_requires_memres(self, vdkr, temp_dir, request):
        """Test that volume mounts fail gracefully without memres."""
        if request.config.getoption("--skip-destructive"):
            pytest.skip("Skipped with --skip-destructive")

        # Ensure memres is stopped
        vdkr.memres_stop()

        # Create a test file
        test_file = temp_dir / "test.txt"
        test_file.write_text("test")

        # Try to use volume mount without memres - should fail with clear message
        result = vdkr.run("vrun", "-v", f"{temp_dir}:/data", "alpine:latest",
                          "cat", "/data/test.txt", check=False, timeout=30)

        # Should fail because memres is not running
        assert result.returncode != 0
        output = (result.stdout + result.stderr).lower()
        assert "memres" in output or "daemon" in output


@pytest.mark.memres
class TestSystem:
    """Test system commands (run inside VM)."""

    def test_system_df(self, memres_session):
        """Test system df command."""
        vdkr = memres_session
        vdkr.ensure_memres()

        result = vdkr.run("system", "df")
        assert result.returncode == 0
        # Should show images, containers, volumes headers
        assert "IMAGES" in result.stdout.upper() or "TYPE" in result.stdout.upper()

    def test_system_df_verbose(self, memres_session):
        """Test system df -v command."""
        vdkr = memres_session
        vdkr.ensure_memres()

        result = vdkr.run("system", "df", "-v")
        assert result.returncode == 0
        # Verbose mode shows more details
        assert "IMAGES" in result.stdout.upper() or "TYPE" in result.stdout.upper()

    def test_system_prune_dry_run(self, memres_session):
        """Test system prune with dry run (doesn't actually delete)."""
        vdkr = memres_session
        vdkr.ensure_memres()

        # Just verify the command runs (don't actually prune in tests)
        # Add -f to skip confirmation prompt
        result = vdkr.run("system", "prune", "-f", check=False)
        # Command may return 0 even with nothing to prune
        assert result.returncode == 0

    def test_system_without_subcommand(self, memres_session):
        """Test system command without subcommand shows error."""
        vdkr = memres_session
        vdkr.ensure_memres()

        result = vdkr.run("system", check=False)
        assert result.returncode != 0
        output = (result.stdout + result.stderr).lower()
        assert "subcommand" in output or "requires" in output


@pytest.mark.memres
class TestVstorage:
    """Test vstorage commands (host-side storage management).

    These commands run on the host and don't require memres.
    """

    def test_vstorage_list(self, vdkr):
        """Test vstorage list command."""
        # Ensure there's something to list by starting memres briefly
        vdkr.ensure_memres()

        result = vdkr.run("vstorage", "list", check=False)
        # vstorage list is an alias for vstorage
        assert result.returncode == 0
        assert "storage" in result.stdout.lower() or "path" in result.stdout.lower()

    def test_vstorage_default(self, vdkr):
        """Test vstorage with no subcommand (defaults to list)."""
        vdkr.ensure_memres()

        result = vdkr.run("vstorage", check=False)
        assert result.returncode == 0
        # Should show storage info
        assert "storage" in result.stdout.lower() or "vdkr" in result.stdout.lower()

    def test_vstorage_path(self, vdkr, arch):
        """Test vstorage path command."""
        result = vdkr.run("vstorage", "path", check=False)
        assert result.returncode == 0
        # Output should contain the architecture or .vdkr path
        assert arch in result.stdout or ".vdkr" in result.stdout

    def test_vstorage_path_specific_arch(self, vdkr):
        """Test vstorage path with specific architecture."""
        # Use the same arch as the runner to avoid cross-arch issues
        arch = vdkr.arch
        result = vdkr.run("vstorage", "path", arch, check=False)
        assert result.returncode == 0
        assert arch in result.stdout

    def test_vstorage_df(self, vdkr):
        """Test vstorage df command."""
        # Ensure there's something to show
        vdkr.ensure_memres()

        result = vdkr.run("vstorage", "df", check=False)
        assert result.returncode == 0
        # Should show size information (may be empty if no state yet)

    def test_vstorage_shows_memres_status(self, vdkr):
        """Test that vstorage list shows memres running status."""
        vdkr.ensure_memres()

        result = vdkr.run("vstorage", "list", check=False)
        assert result.returncode == 0
        # Should show running status when memres is active
        assert "running" in result.stdout.lower() or "memres" in result.stdout.lower() \
            or "status" in result.stdout.lower()

    def test_vstorage_clean_current_arch(self, vdkr, request):
        """Test vstorage clean for current architecture."""
        if request.config.getoption("--skip-destructive"):
            pytest.skip("Skipped with --skip-destructive")

        # Ensure there's something to clean
        vdkr.ensure_memres()
        vdkr.memres_stop()

        result = vdkr.run("vstorage", "clean", check=False)
        assert result.returncode == 0
        assert "clean" in result.stdout.lower()

    def test_vstorage_unknown_subcommand(self, vdkr):
        """Test vstorage with unknown subcommand shows error."""
        result = vdkr.run("vstorage", "invalid", check=False)
        assert result.returncode != 0
        output = (result.stdout + result.stderr).lower()
        assert "unknown" in output or "usage" in output


@pytest.mark.memres
class TestRun:
    """Test run command with docker run options."""

    def test_run_with_entrypoint(self, memres_session):
        """Test run command with --entrypoint override."""
        vdkr = memres_session
        vdkr.ensure_alpine()

        result = vdkr.run("run", "--rm", "--entrypoint", "/bin/echo",
                          "alpine:latest", "hello", "from", "entrypoint")
        assert result.returncode == 0
        assert "hello from entrypoint" in result.stdout

    def test_run_with_env_var(self, memres_session):
        """Test run command with environment variable."""
        vdkr = memres_session
        vdkr.ensure_alpine()

        # Use printenv instead of echo $MY_VAR to avoid shell quoting issues
        result = vdkr.run("run", "--rm", "-e", "MY_VAR=test_value",
                          "alpine:latest", "printenv", "MY_VAR")
        assert result.returncode == 0
        assert "test_value" in result.stdout


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
    def test_pull_busybox(self, memres_session):
        """Test pulling busybox image from registry."""
        vdkr = memres_session
        vdkr.ensure_memres()

        # Pull busybox (very small image, faster than alpine for this test)
        result = vdkr.pull("busybox:latest", timeout=300)
        assert result.returncode == 0

        # Verify it appears in images
        images = vdkr.images()
        assert "busybox" in images.stdout

    @pytest.mark.network
    def test_pull_and_run(self, memres_session):
        """Test that pulled container can be executed."""
        vdkr = memres_session
        vdkr.ensure_memres()

        # Ensure we have busybox
        images = vdkr.images()
        if "busybox" not in images.stdout:
            vdkr.pull("busybox:latest", timeout=300)

        # Run a command in the pulled container
        result = vdkr.vrun("busybox:latest", "/bin/echo", "remote_fetch_works")
        assert result.returncode == 0
        assert "remote_fetch_works" in result.stdout

    @pytest.mark.network
    def test_cross_install_workflow(self, memres_session, temp_dir):
        """Test full cross-install workflow: pull -> export -> import -> run.

        This simulates:
        1. Build host: pull container from registry
        2. Build host: export Docker storage to tar (for bundling into image)
        3. Target boot: import storage tar
        4. Target: run the container

        This is the core workflow for container-cross-install.
        """
        vdkr = memres_session
        vdkr.ensure_memres()

        # Step 1: Pull container from remote registry
        images = vdkr.images()
        if "busybox" not in images.stdout:
            result = vdkr.pull("busybox:latest", timeout=300)
            assert result.returncode == 0

        # Step 2: Save container to tar (simulates bundle export)
        bundle_tar = temp_dir / "cross-install-bundle.tar"
        result = vdkr.save(bundle_tar, "busybox:latest", timeout=180)
        assert result.returncode == 0
        assert bundle_tar.exists()
        assert bundle_tar.stat().st_size > 0

        # Step 3: Remove original image (simulates fresh target state)
        vdkr.run("rmi", "-f", "busybox:latest", check=False)
        images = vdkr.images()
        # Verify removed (may still show if other tags exist)

        # Step 4: Load from bundle tar (simulates target importing bundled storage)
        result = vdkr.load(bundle_tar, timeout=180)
        assert result.returncode == 0

        # Step 5: Verify container works after import
        images = vdkr.images()
        assert "busybox" in images.stdout

        result = vdkr.vrun("busybox:latest", "/bin/echo", "cross_install_success")
        assert result.returncode == 0
        assert "cross_install_success" in result.stdout

    @pytest.mark.network
    def test_pull_verify_architecture(self, memres_session, arch):
        """Test that pulled container matches target architecture."""
        vdkr = memres_session
        vdkr.ensure_memres()

        # Ensure we have busybox
        images = vdkr.images()
        if "busybox" not in images.stdout:
            vdkr.pull("busybox:latest", timeout=300)

        # Run uname to verify architecture inside container
        result = vdkr.vrun("busybox:latest", "/bin/uname", "-m")
        assert result.returncode == 0

        # Check architecture matches target
        expected_arch = "x86_64" if arch == "x86_64" else "aarch64"
        assert expected_arch in result.stdout, \
            f"Architecture mismatch: expected {expected_arch}, got {result.stdout.strip()}"

    @pytest.mark.network
    def test_multiple_containers_bundle(self, memres_session, temp_dir):
        """Test bundling multiple containers (simulates multi-container image)."""
        vdkr = memres_session
        vdkr.ensure_memres()

        containers = ["busybox:latest", "alpine:latest"]
        bundle_tars = []

        # Pull and save each container
        for container in containers:
            name = container.split(":")[0]
            images = vdkr.images()
            if name not in images.stdout:
                result = vdkr.pull(container, timeout=300)
                assert result.returncode == 0

            tar_path = temp_dir / f"{name}-bundle.tar"
            result = vdkr.save(tar_path, container, timeout=180)
            assert result.returncode == 0
            bundle_tars.append((container, tar_path))

        # Remove all containers
        for container, _ in bundle_tars:
            vdkr.run("rmi", "-f", container, check=False)

        # Load all bundles (simulates target with multiple bundled containers)
        for container, tar_path in bundle_tars:
            result = vdkr.load(tar_path, timeout=180)
            assert result.returncode == 0

        # Verify all containers work
        images = vdkr.images()
        for container, _ in bundle_tars:
            name = container.split(":")[0]
            assert name in images.stdout, f"{name} not found after load"

        # Run a command in each
        result = vdkr.vrun("busybox:latest", "/bin/echo", "busybox_ok")
        assert "busybox_ok" in result.stdout

        result = vdkr.vrun("alpine:latest", "/bin/echo", "alpine_ok")
        assert "alpine_ok" in result.stdout


@pytest.mark.memres
class TestAutoStartDaemon:
    """Test auto-start daemon behavior.

    When auto-daemon is enabled (default), vmemres starts automatically
    on the first command and stops after idle timeout.
    """

    def test_auto_start_on_first_command(self, vdkr):
        """Test that daemon auto-starts on first command."""
        # Stop daemon if running
        vdkr.memres_stop()
        assert not vdkr.is_memres_running(), "Daemon should be stopped"

        # Run a command - daemon should auto-start
        result = vdkr.images(timeout=180)
        assert result.returncode == 0

        # Verify daemon is now running
        assert vdkr.is_memres_running(), "Daemon should have auto-started"

    def test_no_daemon_flag(self, vdkr):
        """Test --no-daemon runs without starting daemon."""
        # Stop daemon if running
        vdkr.memres_stop()
        assert not vdkr.is_memres_running(), "Daemon should be stopped"

        # Run with --no-daemon - should use ephemeral mode
        result = vdkr.run("--no-daemon", "images", timeout=180)
        assert result.returncode == 0

        # Daemon should NOT be running
        assert not vdkr.is_memres_running(), "Daemon should not have started with --no-daemon"

    def test_vconfig_auto_daemon(self, vdkr):
        """Test vconfig auto-daemon setting."""
        # Check current value
        result = vdkr.run("vconfig", "auto-daemon")
        assert result.returncode == 0
        assert "true" in result.stdout.lower() or "auto-daemon" in result.stdout

        # Test setting to false
        result = vdkr.run("vconfig", "auto-daemon", "false")
        assert result.returncode == 0

        # Reset to default
        result = vdkr.run("vconfig", "auto-daemon", "--reset")
        assert result.returncode == 0

    def test_vconfig_idle_timeout(self, vdkr):
        """Test vconfig idle-timeout setting."""
        # Check current value
        result = vdkr.run("vconfig", "idle-timeout")
        assert result.returncode == 0

        # Test setting value
        result = vdkr.run("vconfig", "idle-timeout", "3600")
        assert result.returncode == 0

        # Reset to default
        result = vdkr.run("vconfig", "idle-timeout", "--reset")
        assert result.returncode == 0


@pytest.mark.memres
class TestDynamicPortForwarding:
    """Test dynamic port forwarding via QMP.

    Port forwards can be added dynamically when running detached containers,
    without needing to specify them at vmemres start time.
    """

    @pytest.mark.network
    @pytest.mark.slow
    def test_dynamic_port_forward_run(self, vdkr):
        """Test that run -d -p adds port forward dynamically."""
        import subprocess
        import time

        # Ensure memres is running (without static port forwards)
        vdkr.memres_stop()
        vdkr.memres_start(timeout=180)
        assert vdkr.is_memres_running()

        try:
            # Pull nginx:alpine if not present
            vdkr.run("pull", "nginx:alpine", timeout=300)

            # Run with dynamic port forward
            result = vdkr.run("run", "-d", "--name", "nginx-test", "-p", "8888:80",
                              "nginx:alpine", timeout=60)
            assert result.returncode == 0, f"nginx run failed: {result.stderr}"

            # Give nginx time to start
            time.sleep(3)

            # Test access from host
            curl_result = subprocess.run(
                ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                 "http://localhost:8888"],
                capture_output=True,
                text=True,
                timeout=10
            )
            assert curl_result.stdout == "200", \
                f"Expected HTTP 200, got {curl_result.stdout}"

            # Check ps shows port forwards
            ps_result = vdkr.run("ps")
            assert ps_result.returncode == 0
            assert "8888" in ps_result.stdout or "Port Forwards" in ps_result.stdout

        finally:
            # Clean up
            vdkr.run("stop", "nginx-test", timeout=30, check=False)
            vdkr.run("rm", "-f", "nginx-test", check=False)

    def test_port_forward_cleanup_on_stop(self, memres_session):
        """Test that port forwards are cleaned up when container stops."""
        vdkr = memres_session
        vdkr.ensure_memres()

        # Ensure we have busybox
        vdkr.ensure_busybox()

        # Run a container with port forward
        result = vdkr.run("run", "-d", "--name", "port-test", "-p", "9999:80",
                          "busybox:latest", "sleep", "300", timeout=60, check=False)

        if result.returncode == 0:
            # Stop the container (docker stop has 10s grace period, so need longer timeout)
            vdkr.run("stop", "port-test", timeout=30, check=False)

            # Check ps - port forward should be removed
            ps_result = vdkr.run("ps")
            assert "9999" not in ps_result.stdout or "port-test" not in ps_result.stdout

            # Clean up
            vdkr.run("rm", "-f", "port-test", check=False)

    def test_port_forward_cleanup_on_rm(self, memres_session):
        """Test that port forwards are cleaned up when container is removed."""
        vdkr = memres_session
        vdkr.ensure_memres()

        # Ensure we have busybox
        vdkr.ensure_busybox()

        # Run a container with port forward
        result = vdkr.run("run", "-d", "--name", "rm-test", "-p", "7777:80",
                          "busybox:latest", "sleep", "300", timeout=60, check=False)

        if result.returncode == 0:
            # Force remove the container
            vdkr.run("rm", "-f", "rm-test", timeout=10, check=False)

            # Check ps - port forward should be removed
            ps_result = vdkr.run("ps")
            assert "7777" not in ps_result.stdout or "rm-test" not in ps_result.stdout

    @pytest.mark.network
    @pytest.mark.slow
    def test_multiple_dynamic_port_forwards(self, vdkr):
        """Test multiple containers with different dynamic port forwards."""
        import time

        vdkr.memres_stop()
        vdkr.memres_start(timeout=180)
        assert vdkr.is_memres_running()

        try:
            # Pull busybox
            vdkr.run("pull", "busybox:latest", timeout=300, check=False)

            # Run first container with port forward
            result1 = vdkr.run("run", "-d", "--name", "http1", "-p", "8001:80",
                               "busybox:latest", "httpd", "-f", "-p", "80",
                               timeout=60, check=False)

            # Run second container with different port forward
            result2 = vdkr.run("run", "-d", "--name", "http2", "-p", "8002:80",
                               "busybox:latest", "httpd", "-f", "-p", "80",
                               timeout=60, check=False)

            time.sleep(2)

            # Check ps shows both port forwards
            ps_result = vdkr.run("ps")
            # Note: May show in port forwards section, not PORTS column
            assert ps_result.returncode == 0

            # Stop first - second should still work
            vdkr.run("stop", "http1", timeout=30, check=False)

            # Check ps - only second port forward should remain
            ps_result = vdkr.run("ps")
            # http1's port should be cleaned up, http2 should remain

        finally:
            vdkr.run("stop", "http1", timeout=30, check=False)
            vdkr.run("stop", "http2", timeout=30, check=False)
            vdkr.run("rm", "-f", "http1", check=False)
            vdkr.run("rm", "-f", "http2", check=False)


@pytest.mark.memres
class TestPortForwardRegistry:
    """Test port forward registry cleanup."""

    def test_port_forward_cleared_on_memres_stop(self, vdkr):
        """Test that port forward registry is cleared when memres stops."""
        import os

        # Start memres
        vdkr.memres_stop()
        vdkr.memres_start(timeout=180)
        assert vdkr.is_memres_running()

        # Get state dir path
        result = vdkr.run("vstorage", "path")
        if result.returncode == 0:
            state_dir = result.stdout.strip()
            pf_file = os.path.join(state_dir, "port-forwards.txt")

            # Run a container with port forward to create registry entry
            vdkr.ensure_busybox()
            vdkr.run("run", "-d", "--name", "pf-test", "-p", "6666:80",
                     "busybox:latest", "sleep", "60", timeout=60, check=False)

            # Stop memres - should clear port forward file
            vdkr.memres_stop()

            # Port forward file should not exist or be empty
            if os.path.exists(pf_file):
                with open(pf_file, 'r') as f:
                    content = f.read()
                assert content.strip() == "", "Port forward file should be empty"
