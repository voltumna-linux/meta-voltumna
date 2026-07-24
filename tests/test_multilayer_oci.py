# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Tests for multi-layer OCI container image support.

These tests verify that OCI_LAYER_MODE = "multi" creates proper multi-layer
OCI images and that layer caching works correctly.

Run with:
    pytest tests/test_multilayer_oci.py -v --poky-dir /opt/bruce/poky

Environment variables:
    POKY_DIR: Path to poky directory (default: /opt/bruce/poky)
    BUILD_DIR: Path to build directory (default: $POKY_DIR/build)
    MACHINE: Target machine (default: qemux86-64)

Note: These tests require a configured Yocto build environment.
"""

import os
import json
import subprocess
import shutil
import pytest
from pathlib import Path


# Note: Command line options are defined in conftest.py


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


@pytest.fixture(scope="module")
def layer_cache_dir(build_dir, machine):
    """Path to OCI layer cache directory."""
    return build_dir / "oci-layer-cache" / machine


def run_bitbake(build_dir, recipe, task=None, extra_args=None, timeout=1800):
    """Run a bitbake command within the Yocto environment."""
    # Build the bitbake command
    bb_cmd = "bitbake"
    if task:
        bb_cmd += f" -c {task}"
    bb_cmd += f" {recipe}"
    if extra_args:
        bb_cmd += " " + " ".join(extra_args)

    # Source oe-init-build-env and run bitbake
    poky_dir = build_dir.parent
    full_cmd = f"bash -c 'cd {poky_dir} && source oe-init-build-env {build_dir} >/dev/null 2>&1 && {bb_cmd}'"

    result = subprocess.run(
        full_cmd,
        shell=True,
        cwd=build_dir,
        timeout=timeout,
        capture_output=True,
        text=True,
    )
    return result


def get_oci_layer_count(oci_dir):
    """Get the number of layers in an OCI image using skopeo."""
    result = subprocess.run(
        ["skopeo", "inspect", f"oci:{oci_dir}"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        return None

    try:
        data = json.loads(result.stdout)
        return len(data.get("Layers", []))
    except json.JSONDecodeError:
        return None


def get_task_log(build_dir, machine, recipe, task):
    """Get the path to a bitbake task log."""
    work_dir = build_dir / "tmp" / "work"

    # Find the work directory for the recipe
    for arch_dir in work_dir.glob(f"*{machine}*"):
        recipe_dir = arch_dir / recipe
        if recipe_dir.exists():
            # Find the latest version directory
            for version_dir in sorted(recipe_dir.iterdir(), reverse=True):
                log_dir = version_dir / "temp"
                logs = list(log_dir.glob(f"log.{task}.*"))
                if logs:
                    return max(logs, key=lambda p: p.stat().st_mtime)
    return None


class TestMultiLayerOCIClass:
    """Test OCI multi-layer bbclass functionality."""

    def test_bbclass_exists(self, meta_virt_dir):
        """Test that the image-oci.bbclass file exists."""
        class_file = meta_virt_dir / "classes" / "image-oci.bbclass"
        assert class_file.exists(), f"Class file not found: {class_file}"

    def test_umoci_inc_exists(self, meta_virt_dir):
        """Test that the image-oci-umoci.inc file exists."""
        inc_file = meta_virt_dir / "classes" / "image-oci-umoci.inc"
        assert inc_file.exists(), f"Include file not found: {inc_file}"

    def test_multilayer_recipe_exists(self, meta_virt_dir):
        """Test that the multi-layer demo recipe exists."""
        recipe = meta_virt_dir / "recipes-demo" / "images" / "app-container-multilayer.bb"
        assert recipe.exists(), f"Recipe not found: {recipe}"

    def test_cache_variables_defined(self, meta_virt_dir):
        """Test that layer caching variables are defined in bbclass."""
        class_file = meta_virt_dir / "classes" / "image-oci.bbclass"
        content = class_file.read_text()

        assert "OCI_LAYER_CACHE" in content, "OCI_LAYER_CACHE not defined"
        assert "OCI_LAYER_CACHE_DIR" in content, "OCI_LAYER_CACHE_DIR not defined"

    def test_layer_mode_variables_defined(self, meta_virt_dir):
        """Test that layer mode variables are defined in bbclass."""
        class_file = meta_virt_dir / "classes" / "image-oci.bbclass"
        content = class_file.read_text()

        assert "OCI_LAYER_MODE" in content, "OCI_LAYER_MODE not defined"
        assert "OCI_LAYERS" in content, "OCI_LAYERS not defined"


class TestMultiLayerOCIBuild:
    """Test building multi-layer OCI images."""

    @pytest.mark.slow
    def test_multilayer_recipe_builds(self, build_dir):
        """Test that app-container-multilayer recipe builds successfully."""
        result = run_bitbake(build_dir, "app-container-multilayer", timeout=3600)

        if result.returncode != 0:
            if "Nothing PROVIDES" in result.stderr:
                pytest.skip("app-container-multilayer recipe not available")
            pytest.fail(f"Build failed:\nstdout: {result.stdout}\nstderr: {result.stderr}")

    @pytest.mark.slow
    def test_multilayer_produces_correct_layers(self, build_dir, deploy_dir):
        """Test that multi-layer build produces 3 layers."""
        # Ensure the recipe is built
        result = run_bitbake(build_dir, "app-container-multilayer", timeout=3600)
        if result.returncode != 0:
            pytest.skip("Build failed, skipping layer count check")

        # Find the OCI directory
        oci_dirs = list(deploy_dir.glob("app-container-multilayer*-oci"))
        assert len(oci_dirs) > 0, "No OCI directory found for app-container-multilayer"

        # Get the actual OCI directory (resolve symlink if needed)
        oci_dir = oci_dirs[0]
        if oci_dir.is_symlink():
            oci_dir = oci_dir.resolve()

        # Check layer count
        layer_count = get_oci_layer_count(oci_dir)
        assert layer_count is not None, f"Failed to inspect OCI image: {oci_dir}"
        assert layer_count == 3, f"Expected 3 layers, got {layer_count}"


class TestLayerCaching:
    """Test OCI layer caching functionality."""

    @pytest.mark.slow
    def test_cache_directory_created(self, build_dir, layer_cache_dir):
        """Test that the layer cache directory is created after build."""
        # Run the build
        result = run_bitbake(build_dir, "app-container-multilayer", timeout=3600)
        if result.returncode != 0:
            pytest.skip("Build failed, skipping cache test")

        # Check cache directory exists
        assert layer_cache_dir.exists(), f"Cache directory not created: {layer_cache_dir}"

    @pytest.mark.slow
    def test_cache_entries_exist(self, build_dir, layer_cache_dir):
        """Test that cache entries are created for each layer."""
        # Run the build
        result = run_bitbake(build_dir, "app-container-multilayer", timeout=3600)
        if result.returncode != 0:
            pytest.skip("Build failed, skipping cache test")

        # Skip if cache dir doesn't exist
        if not layer_cache_dir.exists():
            pytest.skip("Cache directory not found")

        # Check for cache entries (format: {hash}-{layer_name})
        cache_entries = list(layer_cache_dir.iterdir())
        assert len(cache_entries) >= 3, f"Expected at least 3 cache entries, found {len(cache_entries)}"

        # Check for expected layer names
        entry_names = [e.name for e in cache_entries]
        has_base = any("base" in name for name in entry_names)
        has_shell = any("shell" in name for name in entry_names)
        has_app = any("app" in name for name in entry_names)

        assert has_base, f"No cache entry for 'base' layer. Found: {entry_names}"
        assert has_shell, f"No cache entry for 'shell' layer. Found: {entry_names}"
        assert has_app, f"No cache entry for 'app' layer. Found: {entry_names}"

    @pytest.mark.slow
    def test_cache_marker_file(self, build_dir, layer_cache_dir):
        """Test that cache entries have marker files."""
        # Run the build
        result = run_bitbake(build_dir, "app-container-multilayer", timeout=3600)
        if result.returncode != 0:
            pytest.skip("Build failed, skipping cache test")

        if not layer_cache_dir.exists():
            pytest.skip("Cache directory not found")

        # Check each cache entry has a marker file
        cache_entries = [e for e in layer_cache_dir.iterdir() if e.is_dir()]
        for entry in cache_entries:
            marker = entry / ".oci-layer-cache"
            assert marker.exists(), f"No marker file in cache entry: {entry}"

            # Check marker content
            content = marker.read_text()
            assert "cache_key=" in content
            assert "layer_name=" in content
            assert "created=" in content

    @pytest.mark.slow
    def test_cache_hit_on_rebuild(self, build_dir, machine):
        """Test that cache hits occur on rebuild."""
        # First build - should have cache misses
        result = run_bitbake(build_dir, "app-container-multilayer", timeout=3600)
        if result.returncode != 0:
            pytest.skip("First build failed")

        # Clean the work directory to force re-run of do_image_oci
        work_pattern = f"tmp/work/*{machine}*/app-container-multilayer/*/oci-layer-rootfs"
        for work_dir in build_dir.glob(work_pattern):
            if work_dir.exists():
                shutil.rmtree(work_dir)

        # Remove stamp file to force task re-run
        stamp_pattern = f"tmp/stamps/*{machine}*/app-container-multilayer/*.do_image_oci*"
        for stamp in build_dir.glob(stamp_pattern):
            stamp.unlink()

        # Second build - should have cache hits
        result = run_bitbake(build_dir, "app-container-multilayer", timeout=3600)
        if result.returncode != 0:
            pytest.fail(f"Second build failed:\n{result.stderr}")

        # Check the log for cache hit messages
        log_file = get_task_log(build_dir, machine, "app-container-multilayer", "do_image_oci")
        if log_file and log_file.exists():
            log_content = log_file.read_text()
            assert "OCI Cache HIT" in log_content, \
                "No cache hits found in log. Expected 'OCI Cache HIT' messages."
            # Count hits vs misses
            hits = log_content.count("OCI Cache HIT")
            misses = log_content.count("OCI Cache MISS")
            assert hits >= 3, f"Expected at least 3 cache hits, got {hits} hits and {misses} misses"


class TestSingleLayerBackwardCompat:
    """Test that single-layer mode (default) still works."""

    @pytest.mark.slow
    def test_single_layer_recipe_builds(self, build_dir, meta_virt_dir):
        """Test that a single-layer OCI recipe still builds."""
        # Check if app-container (single-layer) recipe exists
        recipe = meta_virt_dir / "recipes-demo" / "images" / "app-container.bb"
        if not recipe.exists():
            pytest.skip("app-container recipe not found")

        result = run_bitbake(build_dir, "app-container", timeout=3600)
        if result.returncode != 0:
            if "Nothing PROVIDES" in result.stderr:
                pytest.skip("app-container recipe not available")
            pytest.fail(f"Build failed: {result.stderr}")

    @pytest.mark.slow
    def test_single_layer_produces_one_layer(self, build_dir, deploy_dir, meta_virt_dir):
        """Test that single-layer build produces 1 layer."""
        # Check if recipe exists
        recipe = meta_virt_dir / "recipes-demo" / "images" / "app-container.bb"
        if not recipe.exists():
            pytest.skip("app-container recipe not found")

        result = run_bitbake(build_dir, "app-container", timeout=3600)
        if result.returncode != 0:
            pytest.skip("Build failed")

        # Find the OCI directory
        oci_dirs = list(deploy_dir.glob("app-container-*-oci"))
        # Filter out multilayer
        oci_dirs = [d for d in oci_dirs if "multilayer" not in d.name]

        if not oci_dirs:
            pytest.skip("No OCI directory found for app-container")

        oci_dir = oci_dirs[0]
        if oci_dir.is_symlink():
            oci_dir = oci_dir.resolve()

        layer_count = get_oci_layer_count(oci_dir)
        assert layer_count is not None, f"Failed to inspect OCI image: {oci_dir}"
        assert layer_count == 1, f"Expected 1 layer for single-layer mode, got {layer_count}"


class TestTwoLayerBaseImage:
    """Test two-layer OCI images using OCI_BASE_IMAGE."""

    def test_layered_recipe_exists(self, meta_virt_dir):
        """Test that the two-layer demo recipe exists."""
        recipe = meta_virt_dir / "recipes-demo" / "images" / "app-container-layered.bb"
        assert recipe.exists(), f"Recipe not found: {recipe}"

    def test_layered_recipe_uses_base_image(self, meta_virt_dir):
        """Test that the layered recipe uses OCI_BASE_IMAGE."""
        recipe = meta_virt_dir / "recipes-demo" / "images" / "app-container-layered.bb"
        if not recipe.exists():
            pytest.skip("Recipe not found")

        content = recipe.read_text()
        assert "OCI_BASE_IMAGE" in content, "Recipe should use OCI_BASE_IMAGE"
        assert "container-base" in content, "Recipe should use container-base as base"

    @pytest.mark.slow
    def test_layered_recipe_builds(self, build_dir):
        """Test that app-container-layered recipe builds successfully."""
        # First ensure the base image is built
        result = run_bitbake(build_dir, "container-base", timeout=3600)
        if result.returncode != 0:
            if "Nothing PROVIDES" in result.stderr:
                pytest.skip("container-base recipe not available")
            pytest.fail(f"Base image build failed: {result.stderr}")

        # Now build the layered image
        result = run_bitbake(build_dir, "app-container-layered", timeout=3600)
        if result.returncode != 0:
            if "Nothing PROVIDES" in result.stderr:
                pytest.skip("app-container-layered recipe not available")
            pytest.fail(f"Build failed:\nstdout: {result.stdout}\nstderr: {result.stderr}")

    @pytest.mark.slow
    def test_layered_produces_two_layers(self, build_dir, deploy_dir):
        """Test that two-layer build produces 2 layers (base + app)."""
        # Ensure the base is built first
        result = run_bitbake(build_dir, "container-base", timeout=3600)
        if result.returncode != 0:
            pytest.skip("Base image build failed")

        # Build the layered image
        result = run_bitbake(build_dir, "app-container-layered", timeout=3600)
        if result.returncode != 0:
            pytest.skip("Build failed, skipping layer count check")

        # Find the OCI directory
        oci_dirs = list(deploy_dir.glob("app-container-layered*-oci"))
        assert len(oci_dirs) > 0, "No OCI directory found for app-container-layered"

        # Get the actual OCI directory (resolve symlink if needed)
        oci_dir = oci_dirs[0]
        if oci_dir.is_symlink():
            oci_dir = oci_dir.resolve()

        # Check layer count - should be 2 (base + app)
        layer_count = get_oci_layer_count(oci_dir)
        assert layer_count is not None, f"Failed to inspect OCI image: {oci_dir}"
        assert layer_count == 2, f"Expected 2 layers (base + app), got {layer_count}"

    @pytest.mark.slow
    def test_base_image_produces_one_layer(self, build_dir, deploy_dir):
        """Test that container-base (the base image) produces 1 layer."""
        result = run_bitbake(build_dir, "container-base", timeout=3600)
        if result.returncode != 0:
            pytest.skip("Build failed")

        # Find the OCI directory
        oci_dirs = list(deploy_dir.glob("container-base*-oci"))
        if not oci_dirs:
            pytest.skip("No OCI directory found for container-base")

        oci_dir = oci_dirs[0]
        if oci_dir.is_symlink():
            oci_dir = oci_dir.resolve()

        layer_count = get_oci_layer_count(oci_dir)
        assert layer_count is not None, f"Failed to inspect OCI image: {oci_dir}"
        assert layer_count == 1, f"Expected 1 layer for base image, got {layer_count}"


class TestLayerTypes:
    """Test different OCI_LAYERS types."""

    def test_packages_layer_type(self, meta_virt_dir):
        """Test that 'packages' layer type is supported."""
        recipe = meta_virt_dir / "recipes-demo" / "images" / "app-container-multilayer.bb"
        if not recipe.exists():
            pytest.skip("Recipe not found")

        content = recipe.read_text()
        assert "packages" in content, "Recipe should use 'packages' layer type"

    def test_directories_layer_type_documented(self, meta_virt_dir):
        """Test that 'directories' layer type is documented."""
        class_file = meta_virt_dir / "classes" / "image-oci.bbclass"
        content = class_file.read_text()
        assert "directories" in content, "directories layer type should be documented"

    def test_files_layer_type_documented(self, meta_virt_dir):
        """Test that 'files' layer type is documented."""
        class_file = meta_virt_dir / "classes" / "image-oci.bbclass"
        content = class_file.read_text()
        assert "files" in content, "files layer type should be documented"
