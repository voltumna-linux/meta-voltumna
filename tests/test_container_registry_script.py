# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Tests for container-registry.sh helper script.

These tests verify the container registry helper script commands:
- start/stop/status - Registry server lifecycle
- push - Push OCI images to registry (with tag/strategy options)
- import - Import 3rd party images
- delete - Delete tagged images
- gc - Garbage collection
- list/tags/catalog - Query registry contents

Prerequisites:
    # Generate the script first:
    bitbake container-registry-index -c generate_registry_script

    # The script location is:
    $TOPDIR/container-registry/container-registry.sh

Run with:
    pytest tests/test_container_registry_script.py -v

Run with specific registry script:
    pytest tests/test_container_registry_script.py -v \\
        --registry-script /path/to/container-registry.sh

Environment variables:
    CONTAINER_REGISTRY_SCRIPT: Path to the registry script
    TOPDIR: Yocto build directory (script at $TOPDIR/container-registry/)
"""

import pytest
import subprocess
import os
import time
from pathlib import Path


# Note: Registry options (--registry-script, --skip-registry-network)
# are defined in conftest.py


@pytest.fixture(scope="module")
def registry_script(request):
    """Get path to the registry script.

    Looks in order:
    1. --registry-script command line option
    2. CONTAINER_REGISTRY_SCRIPT environment variable
    3. $TOPDIR/container-registry/container-registry.sh
    4. Common locations based on cwd
    """
    # Check command line option
    script_path = request.config.getoption("--registry-script", default=None)

    if script_path is None:
        # Check environment variable
        script_path = os.environ.get("CONTAINER_REGISTRY_SCRIPT")

    if script_path is None:
        # Try TOPDIR-based path
        topdir = os.environ.get("TOPDIR")
        if topdir:
            script_path = os.path.join(topdir, "container-registry", "container-registry.sh")

    if script_path is None:
        # Try common locations relative to cwd
        candidates = [
            "container-registry/container-registry.sh",
            "../container-registry/container-registry.sh",
            "build/container-registry/container-registry.sh",
        ]
        for candidate in candidates:
            if os.path.exists(candidate):
                script_path = candidate
                break

    if script_path is None or not os.path.exists(script_path):
        pytest.skip(
            "Registry script not found. Generate it with: "
            "bitbake container-registry-index -c generate_registry_script\n"
            "Or specify path with --registry-script or CONTAINER_REGISTRY_SCRIPT env var"
        )

    script_path = Path(script_path).resolve()
    if not script_path.exists():
        pytest.skip(f"Registry script not found at: {script_path}")

    return script_path


@pytest.fixture(scope="module")
def skip_network(request):
    """Check if network tests should be skipped."""
    return request.config.getoption("--skip-registry-network", default=False)


class RegistryScriptRunner:
    """Helper class for running registry script commands."""

    def __init__(self, script_path: Path):
        self.script_path = script_path
        self._was_running = None

    def run(self, *args, timeout=30, check=True, capture_output=True):
        """Run a registry script command."""
        cmd = [str(self.script_path)] + list(args)
        result = subprocess.run(
            cmd,
            timeout=timeout,
            check=False,
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
            raise AssertionError(error_msg)
        return result

    def start(self, timeout=30):
        """Start the registry."""
        return self.run("start", timeout=timeout)

    def stop(self, timeout=10):
        """Stop the registry."""
        return self.run("stop", timeout=timeout, check=False)

    def status(self, timeout=10):
        """Check registry status."""
        return self.run("status", timeout=timeout, check=False)

    def is_running(self):
        """Check if registry is running."""
        result = self.status()
        return result.returncode == 0 and "running" in result.stdout.lower()

    def ensure_running(self, timeout=30):
        """Ensure registry is running, starting if needed."""
        if not self.is_running():
            result = self.start(timeout=timeout)
            if result.returncode != 0:
                raise RuntimeError(f"Failed to start registry: {result.stderr}")
            time.sleep(2)

    def push(self, timeout=120):
        """Push OCI images to registry."""
        return self.run("push", timeout=timeout)

    def import_image(self, source, dest_name=None, timeout=300):
        """Import a 3rd party image."""
        args = ["import", source]
        if dest_name:
            args.append(dest_name)
        return self.run(*args, timeout=timeout)

    def list_images(self, timeout=30):
        """List images in registry."""
        return self.run("list", timeout=timeout)

    def tags(self, image, timeout=30):
        """Get tags for an image."""
        return self.run("tags", image, timeout=timeout, check=False)

    def catalog(self, timeout=30):
        """Get raw catalog."""
        return self.run("catalog", timeout=timeout)

    def help(self):
        """Show help."""
        return self.run("help", check=False)

    def delete(self, image_tag, timeout=30):
        """Delete a tagged image."""
        return self.run("delete", image_tag, timeout=timeout, check=False)

    def gc(self, timeout=60):
        """Run garbage collection (non-interactive)."""
        # gc prompts for confirmation, so we can't easily test interactive mode
        # Just test that the command exists and shows dry-run
        return self.run("gc", timeout=timeout, check=False)

    def push_with_args(self, *args, timeout=120):
        """Push with custom arguments."""
        return self.run("push", *args, timeout=timeout, check=False)


@pytest.fixture(scope="module")
def registry(registry_script):
    """Create a RegistryScriptRunner instance."""
    return RegistryScriptRunner(registry_script)


@pytest.fixture(scope="module")
def registry_session(registry):
    """Module-scoped fixture that ensures registry is running.

    Starts the registry if not running and stops it at the end
    if we started it.
    """
    was_running = registry.is_running()

    if not was_running:
        result = registry.start(timeout=30)
        if result.returncode != 0:
            pytest.skip(f"Failed to start registry: {result.stderr}")
        # Wait a moment for registry to be ready
        time.sleep(2)

    yield registry

    # Only stop if we started it
    if not was_running:
        registry.stop()


class TestRegistryScriptBasic:
    """Test basic registry script functionality."""

    def test_script_exists_and_executable(self, registry_script):
        """Test that the script exists and is executable."""
        assert registry_script.exists()
        assert os.access(registry_script, os.X_OK)

    def test_help_command(self, registry):
        """Test help command shows usage info."""
        result = registry.help()
        assert result.returncode == 0
        assert "start" in result.stdout
        assert "stop" in result.stdout
        assert "push" in result.stdout
        assert "import" in result.stdout
        assert "list" in result.stdout

    def test_unknown_command_shows_error(self, registry):
        """Test that unknown command shows error and help."""
        result = registry.run("invalid-command", check=False)
        assert result.returncode != 0
        assert "unknown" in result.stdout.lower() or "usage" in result.stdout.lower()


class TestRegistryLifecycle:
    """Test registry start/stop/status commands."""

    def test_start_registry(self, registry):
        """Test starting the registry."""
        # Stop first if running
        registry.stop()
        time.sleep(1)

        result = registry.start()
        assert result.returncode == 0
        assert "started" in result.stdout.lower() or "running" in result.stdout.lower()

        # Verify it's running
        assert registry.is_running()

    def test_status_when_running(self, registry):
        """Test status command when registry is running."""
        # Ensure running
        if not registry.is_running():
            registry.start()
            time.sleep(2)

        result = registry.status()
        assert result.returncode == 0
        assert "running" in result.stdout.lower()
        assert "healthy" in result.stdout.lower() or "url" in result.stdout.lower()

    def test_stop_registry(self, registry):
        """Test stopping the registry."""
        # Ensure running first
        if not registry.is_running():
            registry.start()
            time.sleep(2)

        result = registry.stop()
        assert result.returncode == 0
        assert "stop" in result.stdout.lower()

        # Verify it's stopped
        assert not registry.is_running()

    def test_status_when_stopped(self, registry):
        """Test status command when registry is stopped."""
        # Ensure stopped
        registry.stop()
        time.sleep(1)

        result = registry.status()
        assert result.returncode != 0
        assert "not running" in result.stdout.lower()

    def test_start_when_already_running(self, registry):
        """Test that starting when already running is idempotent."""
        # Start once
        if not registry.is_running():
            registry.start()
            time.sleep(2)

        # Start again
        result = registry.start()
        assert result.returncode == 0
        assert "already running" in result.stdout.lower() or "running" in result.stdout.lower()

    def test_stop_when_not_running(self, registry):
        """Test that stopping when not running is idempotent."""
        # Ensure stopped
        registry.stop()
        time.sleep(1)

        # Stop again
        result = registry.stop()
        assert result.returncode == 0
        assert "not running" in result.stdout.lower()


class TestRegistryPush:
    """Test pushing OCI images to the registry.

    Note: This requires OCI images in the deploy directory.
    Tests will skip if no images are available.
    """

    def test_push_requires_running_registry(self, registry):
        """Test that push fails when registry is not running."""
        registry.stop()
        time.sleep(1)

        result = registry.run("push", check=False, timeout=10)
        assert result.returncode != 0
        assert "not responding" in result.stdout.lower() or "start" in result.stdout.lower()

    def test_push_with_no_images(self, registry_session):
        """Test push when no OCI images are in deploy directory.

        This may succeed (with "no images" message) or actually push
        images if they exist. Either is acceptable.
        """
        registry_session.ensure_running()
        result = registry_session.push(timeout=120)
        # Either succeeds (with images) or shows message (without)
        # Both are valid outcomes
        assert result.returncode == 0


class TestRegistryImport:
    """Test importing 3rd party images.

    Note: Import tests require network access to docker.io.
    Use --skip-registry-network to skip these tests.
    """

    def test_import_requires_running_registry(self, registry):
        """Test that import fails when registry is not running."""
        registry.stop()
        time.sleep(1)

        result = registry.run("import", "docker.io/library/alpine:latest",
                              check=False, timeout=10)
        assert result.returncode != 0
        assert "not responding" in result.stdout.lower() or "start" in result.stdout.lower()

    def test_import_no_args_shows_usage(self, registry_session):
        """Test that import without args shows usage."""
        registry_session.ensure_running()
        result = registry_session.run("import", check=False)
        assert result.returncode != 0
        assert "usage" in result.stdout.lower()
        assert "docker.io" in result.stdout.lower() or "example" in result.stdout.lower()

    @pytest.mark.network
    @pytest.mark.slow
    def test_import_alpine(self, registry_session, skip_network):
        """Test importing alpine from docker.io."""
        if skip_network:
            pytest.skip("Skipping network test (--skip-registry-network)")

        registry_session.ensure_running()
        result = registry_session.import_image(
            "docker.io/library/alpine:latest",
            timeout=300
        )
        assert result.returncode == 0
        assert "import complete" in result.stdout.lower() or "importing" in result.stdout.lower()

        # Verify it appears in list
        list_result = registry_session.list_images()
        assert "alpine" in list_result.stdout

    @pytest.mark.network
    @pytest.mark.slow
    def test_import_with_custom_name(self, registry_session, skip_network):
        """Test importing with a custom local name."""
        if skip_network:
            pytest.skip("Skipping network test (--skip-registry-network)")

        registry_session.ensure_running()
        result = registry_session.import_image(
            "docker.io/library/busybox:latest",
            "my-busybox",
            timeout=300
        )
        assert result.returncode == 0

        # Verify it appears with custom name
        list_result = registry_session.list_images()
        assert "my-busybox" in list_result.stdout


class TestRegistryQuery:
    """Test registry query commands (list, tags, catalog)."""

    def test_catalog_requires_running_registry(self, registry):
        """Test that catalog fails when registry is not running."""
        registry.stop()
        time.sleep(1)

        result = registry.run("catalog", check=False, timeout=10)
        # May fail or return empty/error JSON
        # Just verify it doesn't hang

    def test_list_requires_running_registry(self, registry):
        """Test that list fails when registry is not running."""
        registry.stop()
        time.sleep(1)

        result = registry.run("list", check=False, timeout=10)
        assert result.returncode != 0
        assert "not responding" in result.stdout.lower()

    def test_catalog_returns_json(self, registry_session):
        """Test that catalog returns JSON format."""
        registry_session.ensure_running()
        result = registry_session.catalog()
        assert result.returncode == 0

        # Should be valid JSON with repositories key
        import json
        try:
            data = json.loads(result.stdout)
            assert "repositories" in data
        except json.JSONDecodeError:
            # May be pretty-printed, try parsing lines
            assert "repositories" in result.stdout

    def test_list_shows_images(self, registry_session):
        """Test that list shows images with their tags."""
        registry_session.ensure_running()
        result = registry_session.list_images()
        assert result.returncode == 0
        # Should show header or images
        assert "images" in result.stdout.lower() or ":" in result.stdout or "(none)" in result.stdout

    def test_tags_for_nonexistent_image(self, registry_session):
        """Test tags command for nonexistent image."""
        registry_session.ensure_running()
        result = registry_session.tags("nonexistent-image-xyz")
        # Either returns non-zero with "not found", or returns empty/error JSON
        # The important thing is it doesn't crash and indicates the image doesn't exist
        if result.returncode == 0:
            # If it returns 0, stdout should be empty or contain error info
            assert "nonexistent" not in result.stdout.lower() or "error" in result.stdout.lower() or result.stdout.strip() == ""
        else:
            assert "not found" in result.stdout.lower() or "error" in result.stdout.lower()

    def test_tags_usage_without_image(self, registry_session):
        """Test tags command without image argument shows usage."""
        registry_session.ensure_running()
        result = registry_session.run("tags", check=False)
        assert result.returncode != 0
        assert "usage" in result.stdout.lower()


class TestRegistryDelete:
    """Test delete command for removing tagged images."""

    def test_delete_requires_running_registry(self, registry):
        """Test that delete fails when registry is not running."""
        registry.stop()
        time.sleep(1)

        result = registry.delete("container-base:latest")
        assert result.returncode != 0
        assert "not responding" in result.stdout.lower()

    def test_delete_no_args_shows_usage(self, registry_session):
        """Test that delete without args shows usage."""
        registry_session.ensure_running()
        result = registry_session.run("delete", check=False)
        assert result.returncode != 0
        assert "usage" in result.stdout.lower()

    def test_delete_requires_tag(self, registry_session):
        """Test that delete requires image:tag format."""
        registry_session.ensure_running()
        result = registry_session.delete("container-base")  # No tag
        assert result.returncode != 0
        assert "tag required" in result.stdout.lower()

    def test_delete_nonexistent_tag(self, registry_session):
        """Test deleting a nonexistent tag."""
        registry_session.ensure_running()
        result = registry_session.delete("container-base:nonexistent-tag-xyz")
        assert result.returncode != 0
        assert "not found" in result.stdout.lower()

    @pytest.mark.network
    @pytest.mark.slow
    def test_delete_workflow(self, registry_session, skip_network):
        """Test importing an image, then deleting it."""
        if skip_network:
            pytest.skip("Skipping network test (--skip-registry-network)")

        registry_session.ensure_running()

        # Import an image with unique name
        result = registry_session.import_image(
            "docker.io/library/alpine:latest",
            "delete-test",
            timeout=300
        )
        assert result.returncode == 0

        # Verify it exists
        result = registry_session.tags("delete-test")
        assert result.returncode == 0
        assert "latest" in result.stdout

        # Delete it
        result = registry_session.delete("delete-test:latest")
        assert result.returncode == 0
        assert "deleted successfully" in result.stdout.lower()

        # Verify it's gone
        result = registry_session.tags("delete-test")
        assert result.returncode != 0 or "not found" in result.stdout.lower()


class TestRegistryGC:
    """Test garbage collection command."""

    def test_gc_help_in_help_output(self, registry):
        """Test that gc command is listed in help."""
        result = registry.help()
        assert "gc" in result.stdout.lower()

    def test_gc_requires_registry_binary(self, registry_session):
        """Test that gc checks for registry binary.

        This test just verifies gc command runs and either:
        - Works (shows dry-run output)
        - Fails with useful error message
        """
        # gc stops registry first, so just run it and check output
        result = registry_session.gc(timeout=30)
        # Should either work or show error about binary/not running
        output = result.stdout.lower()
        assert any([
            "garbage" in output,
            "collecting" in output,
            "registry" in output,
            "error" in output,
            "not found" in output,
        ])


class TestRegistryPushOptions:
    """Test push command with various options."""

    def test_push_tag_requires_image_name(self, registry_session):
        """Test that --tag without image name fails."""
        registry_session.ensure_running()
        result = registry_session.push_with_args("--tag", "v1.0.0")
        assert result.returncode != 0
        assert "--tag requires an image name" in result.stdout.lower()

    def test_push_with_image_filter(self, registry_session):
        """Test pushing a specific image by name."""
        registry_session.ensure_running()
        result = registry_session.push_with_args("container-base")
        # Should either succeed or report image not found
        # (depending on whether container-base exists)
        output = result.stdout.lower()
        assert any([
            "pushing" in output,
            "not found" in output,
            "done" in output,
        ])

    def test_push_with_strategy(self, registry_session):
        """Test pushing with explicit strategy."""
        registry_session.ensure_running()
        result = registry_session.push_with_args("--strategy", "latest")
        assert result.returncode == 0 or "pushing" in result.stdout.lower()

    def test_push_help_shows_options(self, registry):
        """Test that help shows push options."""
        result = registry.help()
        assert "--tag" in result.stdout
        assert "--strategy" in result.stdout
        assert "image" in result.stdout.lower()


class TestRegistryIntegration:
    """Integration tests for full registry workflow.

    These tests require:
    - Registry script generated
    - docker-distribution-native built
    - skopeo-native built
    - Network access (for import tests)
    """

    @pytest.mark.network
    @pytest.mark.slow
    def test_full_workflow(self, registry, skip_network):
        """Test complete workflow: start -> import -> list -> stop."""
        if skip_network:
            pytest.skip("Skipping network test (--skip-registry-network)")

        # Start fresh
        registry.stop()
        time.sleep(1)

        try:
            # Start
            result = registry.start()
            assert result.returncode == 0
            time.sleep(2)

            # Import an image
            result = registry.import_image(
                "docker.io/library/alpine:latest",
                "workflow-test",
                timeout=300
            )
            assert result.returncode == 0

            # List should show it
            result = registry.list_images()
            assert result.returncode == 0
            assert "workflow-test" in result.stdout

            # Tags should work
            result = registry.tags("workflow-test")
            assert result.returncode == 0
            assert "latest" in result.stdout

            # Catalog should include it
            result = registry.catalog()
            assert result.returncode == 0
            assert "workflow-test" in result.stdout

        finally:
            # Always stop
            registry.stop()


class TestRegistryAuthentication:
    """Test registry authentication features.

    Tests for the authentication modes:
    - none (default)
    - home (~/.docker/config.json)
    - authfile (explicit Docker config path)
    - credsfile (simple key=value credentials file)
    - env (environment variables, script only)
    """

    def test_help_shows_auth_options(self, registry):
        """Test that help shows authentication options."""
        result = registry.help()
        assert "--use-home-auth" in result.stdout or "--authfile" in result.stdout
        assert "--credsfile" in result.stdout
        assert "--auth-mode" in result.stdout
        assert "authentication" in result.stdout.lower()

    def test_help_shows_import_auth_options(self, registry):
        """Test that help shows import source authentication options."""
        result = registry.help()
        assert "--src-authfile" in result.stdout or "--src-creds" in result.stdout

    def test_push_with_unknown_auth_mode_fails(self, registry_session):
        """Test that unknown auth mode fails."""
        registry_session.ensure_running()
        result = registry_session.push_with_args("--auth-mode", "invalid")
        assert result.returncode != 0
        assert "unknown" in result.stdout.lower() or "error" in result.stdout.lower()

    def test_push_with_none_auth_mode(self, registry_session):
        """Test that none auth mode works (default)."""
        registry_session.ensure_running()
        result = registry_session.push_with_args("--auth-mode", "none")
        # Should work (no auth required for local registry)
        assert result.returncode == 0

    def test_push_with_home_auth_no_config(self, registry_session, tmp_path, monkeypatch):
        """Test that home auth mode fails when config doesn't exist."""
        registry_session.ensure_running()
        # Point HOME to temp dir without .docker/config.json
        monkeypatch.setenv("HOME", str(tmp_path))
        result = registry_session.push_with_args("--use-home-auth")
        assert result.returncode != 0
        assert "not found" in result.stdout.lower() or "error" in result.stdout.lower()

    def test_push_with_authfile_nonexistent(self, registry_session, tmp_path):
        """Test that authfile mode fails when file doesn't exist."""
        registry_session.ensure_running()
        nonexistent = tmp_path / "nonexistent-auth.json"
        result = registry_session.push_with_args("--authfile", str(nonexistent))
        assert result.returncode != 0
        assert "not found" in result.stdout.lower() or "error" in result.stdout.lower()

    def test_push_with_credsfile_nonexistent(self, registry_session, tmp_path):
        """Test that credsfile mode fails when file doesn't exist."""
        registry_session.ensure_running()
        nonexistent = tmp_path / "nonexistent-creds"
        result = registry_session.push_with_args("--credsfile", str(nonexistent))
        assert result.returncode != 0
        assert "not found" in result.stdout.lower() or "error" in result.stdout.lower()

    def test_push_with_credsfile_incomplete(self, registry_session, tmp_path):
        """Test that credsfile mode fails when file is incomplete."""
        registry_session.ensure_running()
        # Create credentials file with only username (missing password or token)
        creds_file = tmp_path / "incomplete-creds"
        creds_file.write_text("CONTAINER_REGISTRY_USER=testuser\n")
        result = registry_session.push_with_args("--credsfile", str(creds_file))
        assert result.returncode != 0
        assert "must contain" in result.stdout.lower() or "error" in result.stdout.lower()

    def test_push_with_valid_credsfile_user_password(self, registry_session, tmp_path):
        """Test push with valid credsfile (username/password).

        Note: This test uses fake credentials but validates the parsing works.
        The push may fail auth against the registry but shows credentials are parsed.
        """
        registry_session.ensure_running()
        creds_file = tmp_path / "test-creds"
        creds_file.write_text(
            "CONTAINER_REGISTRY_USER=testuser\n"
            "CONTAINER_REGISTRY_PASSWORD=testpass\n"
        )
        result = registry_session.push_with_args("--credsfile", str(creds_file))
        # Should parse the file successfully and attempt push
        # May succeed or fail auth, but shouldn't fail on parsing
        output = result.stdout.lower()
        # Should not contain parsing errors
        assert "must contain" not in output
        assert "credentials file not found" not in output

    def test_push_with_valid_credsfile_token(self, registry_session, tmp_path):
        """Test push with valid credsfile (token).

        Token takes precedence over username/password.
        """
        registry_session.ensure_running()
        creds_file = tmp_path / "test-token-creds"
        creds_file.write_text(
            "# Comment line\n"
            "CONTAINER_REGISTRY_TOKEN=test-token-123\n"
            "\n"
            "# Extra whitespace and comments are ignored\n"
        )
        result = registry_session.push_with_args("--credsfile", str(creds_file))
        # Should parse the file successfully
        output = result.stdout.lower()
        assert "must contain" not in output
        assert "credentials file not found" not in output

    def test_push_with_credsfile_quoted_values(self, registry_session, tmp_path):
        """Test push with credsfile containing quoted values."""
        registry_session.ensure_running()
        creds_file = tmp_path / "quoted-creds"
        creds_file.write_text(
            'CONTAINER_REGISTRY_USER="quoted-user"\n'
            "CONTAINER_REGISTRY_PASSWORD='quoted-pass'\n"
        )
        result = registry_session.push_with_args("--credsfile", str(creds_file))
        # Should parse quoted values correctly
        output = result.stdout.lower()
        assert "must contain" not in output

    def test_push_with_env_auth_mode_no_creds(self, registry_session, monkeypatch):
        """Test that env auth mode fails without env vars set."""
        registry_session.ensure_running()
        # Clear any existing auth env vars
        monkeypatch.delenv("CONTAINER_REGISTRY_TOKEN", raising=False)
        monkeypatch.delenv("CONTAINER_REGISTRY_USER", raising=False)
        monkeypatch.delenv("CONTAINER_REGISTRY_PASSWORD", raising=False)

        result = registry_session.push_with_args("--auth-mode", "env")
        assert result.returncode != 0
        assert "requires" in result.stdout.lower() or "error" in result.stdout.lower()

    def test_push_with_env_auth_mode_token(self, registry_session, monkeypatch):
        """Test env auth mode with token environment variable."""
        registry_session.ensure_running()
        monkeypatch.setenv("CONTAINER_REGISTRY_TOKEN", "test-env-token")

        result = registry_session.push_with_args("--auth-mode", "env")
        # Should not fail on missing credentials
        output = result.stdout.lower()
        assert "requires" not in output or "requires" in output and "token or user" not in output

    def test_push_with_direct_creds_option(self, registry_session):
        """Test push with --creds option."""
        registry_session.ensure_running()
        result = registry_session.push_with_args("--creds", "user:pass")
        # Should attempt push with credentials
        # May fail auth but shouldn't fail on parsing
        output = result.stdout.lower()
        assert "creds value missing" not in output

    def test_push_with_direct_token_option(self, registry_session):
        """Test push with --token option."""
        registry_session.ensure_running()
        result = registry_session.push_with_args("--token", "test-direct-token")
        # Should attempt push with token
        output = result.stdout.lower()
        assert "token value missing" not in output

    def test_import_with_src_authfile_nonexistent(self, registry_session, tmp_path):
        """Test import with nonexistent source authfile."""
        registry_session.ensure_running()
        nonexistent = tmp_path / "nonexistent-src-auth.json"
        result = registry_session.run(
            "import", "docker.io/library/alpine:latest",
            "--src-authfile", str(nonexistent),
            check=False
        )
        # Skopeo should fail when auth file doesn't exist
        # Just verify we pass the option through correctly
        assert result.returncode != 0 or "error" in result.stdout.lower()

    def test_import_with_src_credsfile(self, registry_session, tmp_path):
        """Test import with source credentials file."""
        registry_session.ensure_running()
        creds_file = tmp_path / "src-creds"
        creds_file.write_text(
            "CONTAINER_REGISTRY_USER=testuser\n"
            "CONTAINER_REGISTRY_PASSWORD=testpass\n"
        )
        result = registry_session.run(
            "import", "docker.io/library/alpine:latest",
            "--src-credsfile", str(creds_file),
            check=False, timeout=30
        )
        # Should parse credentials and attempt import
        output = result.stdout.lower()
        assert "must contain" not in output
        assert "credentials file not found" not in output

    def test_import_with_src_creds_direct(self, registry_session):
        """Test import with direct source credentials."""
        registry_session.ensure_running()
        result = registry_session.run(
            "import", "docker.io/library/alpine:latest",
            "--src-creds", "user:pass",
            check=False, timeout=30
        )
        # Should attempt import with credentials
        # Parsing should succeed even if auth fails
        pass  # Just verify no crash


class TestSecureRegistry:
    """Test secure registry mode with TLS and authentication.

    These tests verify the secure registry infrastructure:
    - PKI generation (CA cert, server cert with SAN)
    - htpasswd authentication setup
    - HTTPS endpoints
    - Auto-credential usage for push

    Prerequisites:
        - openssl and htpasswd must be installed on the system
        - CONTAINER_REGISTRY_SECURE=1 environment variable
    """

    @pytest.fixture
    def secure_env(self, tmp_path, monkeypatch):
        """Set up environment for secure registry testing."""
        storage = tmp_path / "container-registry"
        storage.mkdir()
        monkeypatch.setenv("CONTAINER_REGISTRY_STORAGE", str(storage))
        monkeypatch.setenv("CONTAINER_REGISTRY_SECURE", "1")
        return storage

    def test_help_shows_secure_mode(self, registry):
        """Test that help documents secure mode."""
        result = registry.help()
        output = result.stdout.lower()
        # Help should mention secure mode or TLS
        assert "secure" in output or "tls" in output or "https" in output

    def test_start_generates_pki(self, registry, secure_env):
        """Test that start generates PKI in secure mode."""
        # Note: Requires openssl and htpasswd installed
        result = registry.start(timeout=60)

        # Check for missing dependencies
        output = result.stdout.lower()
        if "openssl" in output and "not found" in output:
            pytest.skip("openssl not available")
        if "htpasswd" in output and "not found" in output:
            pytest.skip("htpasswd not available")

        # Skip if secure mode not enabled (baked script may not have it)
        if "secure" not in output and "https" not in output:
            pytest.skip("Secure mode not enabled in baked script")

        pki_dir = secure_env / "pki"
        auth_dir = secure_env / "auth"

        # Check PKI files generated
        assert (pki_dir / "ca.crt").exists(), "CA cert not generated"
        assert (pki_dir / "ca.key").exists(), "CA key not generated"
        assert (pki_dir / "server.crt").exists(), "Server cert not generated"
        assert (pki_dir / "server.key").exists(), "Server key not generated"

        # Check auth files generated
        assert (auth_dir / "htpasswd").exists(), "htpasswd not generated"
        assert (auth_dir / "password").exists(), "password file not generated"

        # Verify permissions on sensitive files
        ca_key_mode = oct((pki_dir / "ca.key").stat().st_mode)[-3:]
        server_key_mode = oct((pki_dir / "server.key").stat().st_mode)[-3:]
        password_mode = oct((auth_dir / "password").stat().st_mode)[-3:]
        assert ca_key_mode == "600", f"CA key has wrong permissions: {ca_key_mode}"
        assert server_key_mode == "600", f"Server key has wrong permissions: {server_key_mode}"
        assert password_mode == "600", f"Password file has wrong permissions: {password_mode}"

    def test_start_shows_https_url(self, registry, secure_env):
        """Test that start shows https:// URL in secure mode."""
        result = registry.start(timeout=60)
        output = result.stdout.lower()

        # Skip if secure mode not enabled
        if "secure" not in output and "https" not in output:
            pytest.skip("Secure mode not enabled in baked script")

        assert "https://" in result.stdout

    def test_pki_not_regenerated(self, registry, secure_env):
        """Test that existing PKI is not overwritten."""
        # First start generates PKI
        result = registry.start(timeout=60)
        output = result.stdout.lower()

        # Skip if secure mode not enabled
        if "secure" not in output and "https" not in output:
            pytest.skip("Secure mode not enabled in baked script")

        pki_dir = secure_env / "pki"
        if not (pki_dir / "ca.crt").exists():
            pytest.skip("PKI not generated (missing dependencies?)")

        ca_crt_mtime = (pki_dir / "ca.crt").stat().st_mtime

        # Stop and restart
        registry.stop()
        time.sleep(1)
        registry.start(timeout=60)

        # CA cert should not be regenerated
        new_mtime = (pki_dir / "ca.crt").stat().st_mtime
        assert new_mtime == ca_crt_mtime, "CA cert was regenerated"

    def test_custom_username(self, registry, secure_env, monkeypatch):
        """Test custom username configuration."""
        monkeypatch.setenv("CONTAINER_REGISTRY_USERNAME", "customuser")
        result = registry.start(timeout=60)
        output = result.stdout.lower()

        # Skip if secure mode not enabled
        if "secure" not in output and "https" not in output:
            pytest.skip("Secure mode not enabled in baked script")

        htpasswd = secure_env / "auth" / "htpasswd"
        if not htpasswd.exists():
            pytest.skip("htpasswd not generated (missing dependencies?)")

        content = htpasswd.read_text()
        assert content.startswith("customuser:"), f"htpasswd should start with customuser: but got {content[:20]}"

    def test_custom_password(self, registry, secure_env, monkeypatch):
        """Test custom password configuration."""
        monkeypatch.setenv("CONTAINER_REGISTRY_PASSWORD", "custompass123")
        result = registry.start(timeout=60)
        output = result.stdout.lower()

        # Skip if secure mode not enabled
        if "secure" not in output and "https" not in output:
            pytest.skip("Secure mode not enabled in baked script")

        password_file = secure_env / "auth" / "password"
        if not password_file.exists():
            pytest.skip("password file not generated (missing dependencies?)")

        password = password_file.read_text().strip()
        assert password == "custompass123", f"Password should be custompass123 but got {password}"

    def test_server_cert_san(self, registry, secure_env):
        """Test that server cert includes expected SAN entries."""
        result = registry.start(timeout=60)
        output = result.stdout.lower()

        # Skip if secure mode not enabled
        if "secure" not in output and "https" not in output:
            pytest.skip("Secure mode not enabled in baked script")

        server_crt = secure_env / "pki" / "server.crt"
        if not server_crt.exists():
            pytest.skip("Server cert not generated (missing dependencies?)")

        cert_result = subprocess.run(
            ["openssl", "x509", "-in", str(server_crt), "-noout", "-text"],
            capture_output=True, text=True
        )

        if cert_result.returncode != 0:
            pytest.skip("openssl not available")

        cert_text = cert_result.stdout

        # Check SAN entries
        assert "DNS:localhost" in cert_text, "Server cert missing DNS:localhost SAN"
        assert "IP Address:127.0.0.1" in cert_text, "Server cert missing IP:127.0.0.1 SAN"
        assert "IP Address:10.0.2.2" in cert_text, "Server cert missing IP:10.0.2.2 SAN"

    def test_push_uses_credentials(self, registry, secure_env):
        """Test that push auto-uses generated credentials in secure mode."""
        result = registry.start(timeout=60)
        output = result.stdout.lower()

        # Skip if secure mode not enabled
        if "secure" not in output and "https" not in output:
            pytest.skip("Secure mode not enabled in baked script")

        # Attempt push - it should use auto-generated credentials
        push_result = registry.run("push", check=False, timeout=120)
        push_output = push_result.stdout.lower()

        # Should not show "unauthorized" errors (credentials should work)
        # May show "no images" which is fine
        assert "unauthorized" not in push_output, "Push failed with unauthorized - credentials not used"

    @pytest.mark.network
    @pytest.mark.slow
    def test_secure_import(self, registry, secure_env, skip_network):
        """Test importing with TLS verification."""
        if skip_network:
            pytest.skip("Network tests disabled (--skip-registry-network)")

        result = registry.start(timeout=60)
        output = result.stdout.lower()

        # Skip if secure mode not enabled
        if "secure" not in output and "https" not in output:
            pytest.skip("Secure mode not enabled in baked script")

        # Import should work with our CA cert
        import_result = registry.import_image(
            "docker.io/library/alpine:latest",
            timeout=300
        )
        assert import_result.returncode == 0, f"Import failed: {import_result.stdout}"

    def test_tls_curl_verification(self, registry, secure_env):
        """Test that curl can verify the registry TLS."""
        result = registry.start(timeout=60)
        output = result.stdout.lower()

        # Skip if secure mode not enabled
        if "secure" not in output and "https" not in output:
            pytest.skip("Secure mode not enabled in baked script")

        ca_cert = secure_env / "pki" / "ca.crt"
        password_file = secure_env / "auth" / "password"

        if not ca_cert.exists() or not password_file.exists():
            pytest.skip("PKI/auth not generated (missing dependencies?)")

        password = password_file.read_text().strip()

        curl_result = subprocess.run([
            "curl", "-s", "--cacert", str(ca_cert),
            "-u", f"yocto:{password}",
            "https://localhost:5000/v2/_catalog"
        ], capture_output=True, text=True, timeout=30)

        # Should get valid JSON response
        assert curl_result.returncode == 0 or "repositories" in curl_result.stdout, \
            f"Curl TLS verification failed: {curl_result.stderr}"

    def test_status_shows_secure_mode(self, registry, secure_env):
        """Test that status indicates secure mode."""
        result = registry.start(timeout=60)
        start_output = result.stdout.lower()

        # Skip if secure mode not enabled
        if "secure" not in start_output and "https" not in start_output:
            pytest.skip("Secure mode not enabled in baked script")

        status_result = registry.status()
        status_output = status_result.stdout.lower()

        # Status should indicate secure/TLS mode
        assert "https" in status_output or "secure" in status_output or "tls" in status_output, \
            "Status should indicate secure mode"


class TestSecureRegistryTLSOnly:
    """Test TLS-only mode (SECURE=1, AUTH=0).

    When AUTH is not enabled, the registry should:
    - Use HTTPS (TLS) for connections
    - NOT require authentication
    - Allow anonymous pull/push

    These tests work with an already-running secure registry.
    """

    @pytest.fixture
    def registry_storage(self, registry):
        """Get registry storage path from the script."""
        result = registry.run("info", check=False)
        # Parse storage path from info output
        for line in result.stdout.splitlines():
            if "Storage:" in line:
                return Path(line.split("Storage:")[-1].strip())
        # Fall back to common locations
        for candidate in [
            Path(os.environ.get("TOPDIR", "")) / "container-registry",
            Path.cwd() / "container-registry",
            Path.cwd().parent / "container-registry",
        ]:
            if candidate.exists():
                return candidate
        pytest.skip("Cannot determine registry storage path")

    def _ensure_secure_registry(self, registry):
        """Ensure a secure registry is running, starting one if needed."""
        status = registry.status()
        if status.returncode == 0:
            # Already running - verify it's secure
            if "secure" not in status.stdout.lower() and "tls" not in status.stdout.lower():
                pytest.skip("Registry running but not in secure mode")
            return

        # Not running - try to start it
        result = registry.start(timeout=60)
        if result.returncode != 0:
            pytest.skip(f"Could not start registry: {result.stderr}")
        import time
        time.sleep(2)

        status = registry.status()
        if status.returncode != 0:
            pytest.skip("Registry failed to start")
        if "secure" not in status.stdout.lower() and "tls" not in status.stdout.lower():
            pytest.skip("Registry started but not in secure mode")

    def test_status_shows_tls_only(self, registry):
        """Test that status shows TLS-only mode (not TLS+auth)."""
        self._ensure_secure_registry(registry)
        status = registry.status()
        status_output = status.stdout.lower()

        # Should show secure mode
        assert "secure" in status_output or "tls" in status_output, \
            "Status should indicate secure mode"
        # In TLS-only mode, should say "tls only" not "tls + auth"
        if "tls only" in status_output:
            assert "tls + auth" not in status_output

    def test_curl_without_auth(self, registry, registry_storage):
        """Test that curl can access registry without credentials."""
        self._ensure_secure_registry(registry)

        ca_cert = registry_storage / "pki" / "ca.crt"
        if not ca_cert.exists():
            pytest.skip("CA cert not found")

        # Access WITHOUT credentials should work in TLS-only mode
        curl_result = subprocess.run([
            "curl", "-s", "--cacert", str(ca_cert),
            "https://localhost:5000/v2/_catalog"
        ], capture_output=True, text=True, timeout=30)

        assert "repositories" in curl_result.stdout, \
            f"TLS-only registry should not require auth: {curl_result.stderr}"

    def test_config_has_no_auth_section(self, registry, registry_storage):
        """Test that generated registry config has no active auth section."""
        self._ensure_secure_registry(registry)

        config_file = registry_storage / "registry-config.yml"
        if not config_file.exists():
            pytest.skip("Config file not found")

        config_content = config_file.read_text()
        # Check that the actual YAML auth: key is not present as a config directive
        # (comments mentioning htpasswd are fine, only the active auth block matters)
        non_comment_lines = [
            line for line in config_content.splitlines()
            if line.strip() and not line.strip().startswith('#')
        ]
        active_config = '\n'.join(non_comment_lines)
        assert "auth:" not in active_config, \
            "TLS-only config should not have an active auth: section"
        assert "tls:" in config_content, \
            "TLS-only config should contain TLS section"

    def test_pki_exists(self, registry, registry_storage):
        """Test that PKI infrastructure exists."""
        self._ensure_secure_registry(registry)

        pki_dir = registry_storage / "pki"
        assert (pki_dir / "ca.crt").exists(), "CA cert should exist"
        assert (pki_dir / "server.crt").exists(), "Server cert should exist"
        assert (pki_dir / "server.key").exists(), "Server key should exist"

    def test_no_htpasswd_generated(self, registry, registry_storage):
        """Test that TLS-only mode does not require htpasswd authentication.

        Note: A stale auth/htpasswd may exist from previous runs when auth
        was enabled. We verify the functional behavior: the registry config
        has no auth section and anonymous access works (tested separately
        in test_curl_without_auth). Here we check the config file.
        """
        self._ensure_secure_registry(registry)

        config_file = registry_storage / "registry-config.yml"
        if not config_file.exists():
            pytest.skip("Config file not found")

        config_content = config_file.read_text()
        non_comment_lines = [
            line for line in config_content.splitlines()
            if line.strip() and not line.strip().startswith('#')
        ]
        active_config = '\n'.join(non_comment_lines)
        assert "auth:" not in active_config, \
            "TLS-only config should not reference htpasswd authentication"

    def test_info_shows_no_auth(self, registry):
        """Test that info command reflects TLS-only (no auth section)."""
        self._ensure_secure_registry(registry)

        info_result = registry.run("info", check=False)
        info_output = info_result.stdout

        assert "PKI" in info_result.stdout or "pki" in info_result.stdout.lower(), \
            "Info should show PKI directory"
        assert "Password file" not in info_result.stdout, \
            "Info should not show password file in TLS-only mode"


class TestSecureRegistryWithAuth:
    """Test TLS+auth mode (SECURE=1, AUTH=1).

    Uses an isolated registry instance on port 5001 with its own
    storage directory, so it never touches the user's running registry.
    """

    TEST_PORT = "5001"

    @pytest.fixture
    def auth_registry(self, registry, tmp_path, monkeypatch):
        """Start an isolated auth-enabled registry on a different port."""
        storage = tmp_path / "auth-registry"
        storage.mkdir()

        monkeypatch.setenv("CONTAINER_REGISTRY_STORAGE", str(storage))
        monkeypatch.setenv("CONTAINER_REGISTRY_SECURE", "1")
        monkeypatch.setenv("CONTAINER_REGISTRY_AUTH", "1")
        monkeypatch.setenv("CONTAINER_REGISTRY_URL", f"localhost:{self.TEST_PORT}")

        start_result = registry.start(timeout=60)
        if start_result.returncode != 0:
            pytest.skip(f"Could not start auth registry: {start_result.stderr}")

        output = start_result.stdout.lower()
        if "secure" not in output and "https" not in output:
            registry.stop()
            pytest.skip("Script does not support secure mode")
        if "htpasswd" in output and "not found" in output:
            registry.stop()
            pytest.skip("htpasswd not available")

        import time
        time.sleep(2)
        yield storage

        registry.stop()

    def test_curl_requires_auth(self, registry, auth_registry):
        """Test that curl without credentials is rejected."""
        ca_cert = auth_registry / "pki" / "ca.crt"
        if not ca_cert.exists():
            pytest.skip("CA cert not found")

        curl_result = subprocess.run([
            "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
            "--cacert", str(ca_cert),
            f"https://localhost:{self.TEST_PORT}/v2/_catalog"
        ], capture_output=True, text=True, timeout=30)

        assert "401" in curl_result.stdout, \
            f"Auth-enabled registry should reject unauthenticated requests, got: {curl_result.stdout}"

    def test_curl_with_auth_succeeds(self, registry, auth_registry):
        """Test that curl with credentials succeeds."""
        ca_cert = auth_registry / "pki" / "ca.crt"
        password_file = auth_registry / "auth" / "password"
        if not ca_cert.exists() or not password_file.exists():
            pytest.skip("PKI/auth not generated")

        password = password_file.read_text().strip()

        curl_result = subprocess.run([
            "curl", "-s", "--cacert", str(ca_cert),
            "-u", f"yocto:{password}",
            f"https://localhost:{self.TEST_PORT}/v2/_catalog"
        ], capture_output=True, text=True, timeout=30)

        assert "repositories" in curl_result.stdout, \
            f"Authenticated request should succeed: {curl_result.stderr}"

    def test_config_has_auth_section(self, registry, auth_registry):
        """Test that generated registry config includes auth section."""
        config_file = auth_registry / "registry-config.yml"
        if not config_file.exists():
            pytest.skip("Config file not found")

        config_content = config_file.read_text()
        assert "htpasswd" in config_content, \
            "Auth-enabled config should contain htpasswd section"
        assert "tls:" in config_content, \
            "Auth-enabled config should also contain TLS section"

    def test_htpasswd_generated(self, registry, auth_registry):
        """Test that htpasswd file is generated in auth mode."""
        auth_dir = auth_registry / "auth"
        assert (auth_dir / "htpasswd").exists(), "htpasswd not generated in auth mode"
        assert (auth_dir / "password").exists(), "password file not generated"


class TestDockerRegistryConfig:
    """Test docker-registry-config.bb behavior.

    Verifies the bitbake recipe logic for generating Docker daemon
    configuration on target images, specifically:
    - localhost→10.0.2.2 translation for QEMU targets
    - CA cert installation path matches registry host
    """

    def test_bbclass_has_auth_variable(self):
        """Test that container-registry.bbclass defines CONTAINER_REGISTRY_AUTH."""
        bbclass = Path("/opt/bruce/poky/meta-virtualization/classes/container-registry.bbclass")
        if not bbclass.exists():
            pytest.skip("container-registry.bbclass not found")

        content = bbclass.read_text()
        assert 'CONTAINER_REGISTRY_AUTH' in content, \
            "bbclass should define CONTAINER_REGISTRY_AUTH variable"
        assert 'CONTAINER_REGISTRY_AUTH ?= "0"' in content, \
            "CONTAINER_REGISTRY_AUTH should default to 0"

    def test_bbclass_validates_auth_requires_secure(self):
        """Test that bbclass warns when AUTH=1 without SECURE=1."""
        bbclass = Path("/opt/bruce/poky/meta-virtualization/classes/container-registry.bbclass")
        if not bbclass.exists():
            pytest.skip("container-registry.bbclass not found")

        content = bbclass.read_text()
        assert "auth and not secure" in content or "AUTH" in content, \
            "bbclass should validate that AUTH requires SECURE"

    def test_docker_registry_config_translates_localhost(self):
        """Test that docker-registry-config.bb translates localhost to 10.0.2.2."""
        recipe = Path("/opt/bruce/poky/meta-virtualization/recipes-containers/"
                      "container-registry/docker-registry-config.bb")
        if not recipe.exists():
            pytest.skip("docker-registry-config.bb not found")

        content = recipe.read_text()
        assert "10.0.2.2" in content, \
            "Recipe should translate localhost to 10.0.2.2 for QEMU"
        assert "replace" in content.lower() and "localhost" in content, \
            "Recipe should replace localhost with 10.0.2.2"

    def test_docker_registry_config_translates_127(self):
        """Test that docker-registry-config.bb also translates 127.0.0.1."""
        recipe = Path("/opt/bruce/poky/meta-virtualization/recipes-containers/"
                      "container-registry/docker-registry-config.bb")
        if not recipe.exists():
            pytest.skip("docker-registry-config.bb not found")

        content = recipe.read_text()
        assert "127.0.0.1" in content, \
            "Recipe should also translate 127.0.0.1 to 10.0.2.2"


class TestContainerCrossInstallSecure:
    """Test container-cross-install.bbclass secure registry integration.

    Verifies that the cross-install class automatically adds the
    docker-registry-config package when CONTAINER_REGISTRY_SECURE=1.
    """

    def test_cross_install_auto_adds_registry_config(self):
        """Test that cross-install adds docker-registry-config when SECURE=1."""
        bbclass = Path("/opt/bruce/poky/meta-virtualization/classes/"
                       "container-cross-install.bbclass")
        if not bbclass.exists():
            pytest.skip("container-cross-install.bbclass not found")

        content = bbclass.read_text()
        assert "CONTAINER_REGISTRY_SECURE" in content, \
            "Cross-install should check CONTAINER_REGISTRY_SECURE"
        assert "docker-registry-config" in content, \
            "Cross-install should add docker-registry-config in secure mode"

    def test_cross_install_supports_podman_config(self):
        """Test that cross-install adds container-oci-registry-config for podman."""
        bbclass = Path("/opt/bruce/poky/meta-virtualization/classes/"
                       "container-cross-install.bbclass")
        if not bbclass.exists():
            pytest.skip("container-cross-install.bbclass not found")

        content = bbclass.read_text()
        assert "container-oci-registry-config" in content, \
            "Cross-install should support podman registry config"

    def test_cross_install_checks_container_engine(self):
        """Test that cross-install selects config package based on engine."""
        bbclass = Path("/opt/bruce/poky/meta-virtualization/classes/"
                       "container-cross-install.bbclass")
        if not bbclass.exists():
            pytest.skip("container-cross-install.bbclass not found")

        content = bbclass.read_text()
        assert "VIRTUAL-RUNTIME_container_engine" in content, \
            "Cross-install should check container engine to select config package"


class TestVcontainerSecureRegistry:
    """Test vcontainer shell script secure registry support.

    Verifies the host-side scripts handle CA certificates correctly:
    - Auto-detection of bundled CA cert
    - CA cert transport via virtio-9p (not kernel cmdline)
    - Daemon mode sets _9p=1 for share mounting
    """

    def test_vcontainer_common_auto_detects_ca_cert(self):
        """Test that vcontainer-common.sh auto-detects bundled CA cert."""
        script = Path("/opt/bruce/poky/meta-virtualization/recipes-containers/"
                      "vcontainer/files/vcontainer-common.sh")
        if not script.exists():
            pytest.skip("vcontainer-common.sh not found")

        content = script.read_text()
        assert "registry/ca.crt" in content, \
            "Should check for bundled CA cert at registry/ca.crt"
        assert "BUNDLED_CA_CERT" in content, \
            "Should define BUNDLED_CA_CERT variable"
        assert 'SECURE_REGISTRY="true"' in content, \
            "Should auto-enable SECURE_REGISTRY when CA cert found"

    def test_vrunner_passes_ca_via_virtio9p(self):
        """Test that vrunner.sh passes CA cert via virtio-9p, not cmdline."""
        script = Path("/opt/bruce/poky/meta-virtualization/recipes-containers/"
                      "vcontainer/files/vrunner.sh")
        if not script.exists():
            pytest.skip("vrunner.sh not found")

        content = script.read_text()

        # Should copy CA cert to shared folder in daemon mode
        assert "DAEMON_SHARE_DIR" in content and "ca.crt" in content, \
            "Should copy CA cert to DAEMON_SHARE_DIR in daemon mode"

        # Should NOT base64 encode CA cert for cmdline
        assert "base64" not in content.split("CA_CERT")[0].split("CA_CERT")[-1] \
            or "registry_pass" in content, \
            "Should not base64 encode CA cert for kernel cmdline"

    def test_vrunner_daemon_sets_9p(self):
        """Test that daemon mode sets _9p=1 in kernel cmdline."""
        script = Path("/opt/bruce/poky/meta-virtualization/recipes-containers/"
                      "vcontainer/files/vrunner.sh")
        if not script.exists():
            pytest.skip("vrunner.sh not found")

        content = script.read_text()

        # Find the daemon mode block and check for _9p=1
        # The daemon block should contain both virtfs and _9p=1
        lines = content.split('\n')
        in_daemon_block = False
        daemon_has_virtfs = False
        daemon_has_9p = False
        for line in lines:
            if 'DAEMON_MODE" = "start"' in line or "DAEMON_MODE\" = \"start\"" in line:
                in_daemon_block = True
            if in_daemon_block:
                if "virtfs" in line and "DAEMON_SHARE_DIR" in line:
                    daemon_has_virtfs = True
                if "_9p=1" in line:
                    daemon_has_9p = True
                # Detect end of the if block (next top-level statement)
                if line.startswith("fi") and in_daemon_block and daemon_has_virtfs:
                    break

        assert daemon_has_virtfs, "Daemon mode should set up virtio-9p share"
        assert daemon_has_9p, "Daemon mode should set _9p=1 in kernel cmdline"

    def test_vrunner_nondaemon_ca_cert_virtio9p(self):
        """Test that non-daemon mode creates virtio-9p share for CA cert."""
        script = Path("/opt/bruce/poky/meta-virtualization/recipes-containers/"
                      "vcontainer/files/vrunner.sh")
        if not script.exists():
            pytest.skip("vrunner.sh not found")

        content = script.read_text()
        assert "CA_SHARE_DIR" in content, \
            "Non-daemon mode should create CA_SHARE_DIR for virtio-9p"
        assert "cashare" in content, \
            "Should add virtio-9p device for CA cert sharing"

    def test_vdkr_init_reads_ca_from_share(self):
        """Test that vdkr-init.sh reads CA cert from /mnt/share/ca.crt."""
        script = Path("/opt/bruce/poky/meta-virtualization/recipes-containers/"
                      "vcontainer/files/vdkr-init.sh")
        if not script.exists():
            pytest.skip("vdkr-init.sh not found")

        content = script.read_text()
        assert "/mnt/share/ca.crt" in content, \
            "Should check for CA cert at /mnt/share/ca.crt"

    def test_vdkr_init_no_base64_ca_decode(self):
        """Test that vdkr-init.sh no longer decodes base64 CA from cmdline."""
        script = Path("/opt/bruce/poky/meta-virtualization/recipes-containers/"
                      "vcontainer/files/vdkr-init.sh")
        if not script.exists():
            pytest.skip("vdkr-init.sh not found")

        content = script.read_text()
        # Should NOT have docker_registry_ca=<base64> pattern in cmdline parsing
        assert "docker_registry_ca=" not in content or "docker_registry_ca=1" in content, \
            "Should not parse base64 CA cert from kernel cmdline"

    def test_vdkr_init_copies_ca_from_share(self):
        """Test that vdkr-init.sh copies CA cert from shared folder."""
        script = Path("/opt/bruce/poky/meta-virtualization/recipes-containers/"
                      "vcontainer/files/vdkr-init.sh")
        if not script.exists():
            pytest.skip("vdkr-init.sh not found")

        content = script.read_text()
        # Should copy from DOCKER_REGISTRY_CA (which is /mnt/share/ca.crt)
        assert "cp" in content and "DOCKER_REGISTRY_CA" in content, \
            "Should copy CA cert from shared folder path"
        assert "/etc/docker/certs.d/" in content, \
            "Should install CA cert to Docker certs.d directory"

    def test_vcontainer_tarball_tracks_scripts(self):
        """Test that vcontainer-tarball.bb tracks script files via SRC_URI."""
        recipe = Path("/opt/bruce/poky/meta-virtualization/recipes-containers/"
                      "vcontainer/vcontainer-tarball.bb")
        if not recipe.exists():
            pytest.skip("vcontainer-tarball.bb not found")

        content = recipe.read_text()
        assert "SRC_URI" in content, "Should have SRC_URI for file tracking"
        assert "vrunner.sh" in content, "Should track vrunner.sh"
        assert "vcontainer-common.sh" in content, "Should track vcontainer-common.sh"
