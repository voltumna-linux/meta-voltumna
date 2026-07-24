# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Tests for multi-architecture OCI container support.

These tests verify:
- OCI Image Index detection and platform selection
- Multi-arch import via vdkr/vrunner
- Architecture normalization (aarch64 <-> arm64, x86_64 <-> amd64)
- Backward compatibility with single-arch OCI images

Run with:
    pytest tests/test_multiarch_oci.py -v --poky-dir /opt/bruce/poky

Environment variables:
    POKY_DIR: Path to poky directory (default: /opt/bruce/poky)

Note: Some tests require the shell scripts from meta-virtualization/recipes-containers/vcontainer/files/
"""

import os
import json
import subprocess
import tempfile
import shutil
import pytest
from pathlib import Path


# Note: Command line options are defined in conftest.py


@pytest.fixture(scope="module")
def meta_virt_dir(request):
    """Path to meta-virtualization layer."""
    poky_dir = Path(request.config.getoption("--poky-dir"))
    path = poky_dir / "meta-virtualization"
    if not path.exists():
        pytest.skip(f"meta-virtualization not found: {path}")
    return path


@pytest.fixture(scope="module")
def vcontainer_files_dir(meta_virt_dir):
    """Path to vcontainer shell scripts."""
    path = meta_virt_dir / "recipes-containers" / "vcontainer" / "files"
    if not path.exists():
        pytest.skip(f"vcontainer files not found: {path}")
    return path


@pytest.fixture
def multiarch_oci_dir(tmp_path):
    """Create a mock multi-arch OCI directory for testing.

    Creates an OCI Image Index with two platforms: arm64 and amd64.
    The blobs are minimal mock data sufficient for testing detection.
    """
    oci_dir = tmp_path / "test-multiarch-oci"
    oci_dir.mkdir()

    # Create blobs directory
    blobs = oci_dir / "blobs" / "sha256"
    blobs.mkdir(parents=True)

    # Create mock config for arm64
    arm64_config = {
        "architecture": "arm64",
        "os": "linux",
        "config": {},
        "rootfs": {"type": "layers", "diff_ids": []}
    }
    arm64_config_json = json.dumps(arm64_config)
    arm64_config_digest = create_mock_blob(blobs, arm64_config_json)

    # Create mock config for amd64
    amd64_config = {
        "architecture": "amd64",
        "os": "linux",
        "config": {},
        "rootfs": {"type": "layers", "diff_ids": []}
    }
    amd64_config_json = json.dumps(amd64_config)
    amd64_config_digest = create_mock_blob(blobs, amd64_config_json)

    # Create mock layer blob (shared between both)
    layer_content = b"mock layer content for testing"
    layer_digest = create_mock_blob(blobs, layer_content, binary=True)

    # Create manifest for arm64
    arm64_manifest = {
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.manifest.v1+json",
        "config": {
            "mediaType": "application/vnd.oci.image.config.v1+json",
            "digest": f"sha256:{arm64_config_digest}",
            "size": len(arm64_config_json)
        },
        "layers": [
            {
                "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
                "digest": f"sha256:{layer_digest}",
                "size": len(layer_content)
            }
        ]
    }
    arm64_manifest_json = json.dumps(arm64_manifest)
    arm64_manifest_digest = create_mock_blob(blobs, arm64_manifest_json)

    # Create manifest for amd64
    amd64_manifest = {
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.manifest.v1+json",
        "config": {
            "mediaType": "application/vnd.oci.image.config.v1+json",
            "digest": f"sha256:{amd64_config_digest}",
            "size": len(amd64_config_json)
        },
        "layers": [
            {
                "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
                "digest": f"sha256:{layer_digest}",
                "size": len(layer_content)
            }
        ]
    }
    amd64_manifest_json = json.dumps(amd64_manifest)
    amd64_manifest_digest = create_mock_blob(blobs, amd64_manifest_json)

    # Create OCI Image Index
    index = {
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.index.v1+json",
        "manifests": [
            {
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "digest": f"sha256:{arm64_manifest_digest}",
                "size": len(arm64_manifest_json),
                "platform": {"architecture": "arm64", "os": "linux"}
            },
            {
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "digest": f"sha256:{amd64_manifest_digest}",
                "size": len(amd64_manifest_json),
                "platform": {"architecture": "amd64", "os": "linux"}
            }
        ]
    }

    (oci_dir / "index.json").write_text(json.dumps(index, indent=2))
    (oci_dir / "oci-layout").write_text('{"imageLayoutVersion": "1.0.0"}')

    return oci_dir


@pytest.fixture
def singlearch_oci_dir(tmp_path):
    """Create a mock single-arch OCI directory for testing.

    Creates a standard single-arch OCI without platform info in index.json.
    """
    oci_dir = tmp_path / "test-singlearch-oci"
    oci_dir.mkdir()

    # Create blobs directory
    blobs = oci_dir / "blobs" / "sha256"
    blobs.mkdir(parents=True)

    # Create mock config
    config = {
        "architecture": "amd64",
        "os": "linux",
        "config": {},
        "rootfs": {"type": "layers", "diff_ids": []}
    }
    config_json = json.dumps(config)
    config_digest = create_mock_blob(blobs, config_json)

    # Create mock layer
    layer_content = b"mock layer content"
    layer_digest = create_mock_blob(blobs, layer_content, binary=True)

    # Create manifest
    manifest = {
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.manifest.v1+json",
        "config": {
            "mediaType": "application/vnd.oci.image.config.v1+json",
            "digest": f"sha256:{config_digest}",
            "size": len(config_json)
        },
        "layers": [
            {
                "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
                "digest": f"sha256:{layer_digest}",
                "size": len(layer_content)
            }
        ]
    }
    manifest_json = json.dumps(manifest)
    manifest_digest = create_mock_blob(blobs, manifest_json)

    # Create standard index.json WITHOUT platform info
    index = {
        "schemaVersion": 2,
        "manifests": [
            {
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "digest": f"sha256:{manifest_digest}",
                "size": len(manifest_json)
            }
        ]
    }

    (oci_dir / "index.json").write_text(json.dumps(index, indent=2))
    (oci_dir / "oci-layout").write_text('{"imageLayoutVersion": "1.0.0"}')

    return oci_dir


def create_mock_blob(blobs_dir, content, binary=False):
    """Create a mock blob and return its digest (without sha256: prefix)."""
    import hashlib

    if isinstance(content, str):
        content_bytes = content.encode('utf-8')
    else:
        content_bytes = content

    digest = hashlib.sha256(content_bytes).hexdigest()
    blob_path = blobs_dir / digest

    if binary:
        blob_path.write_bytes(content_bytes)
    else:
        blob_path.write_text(content)

    return digest


def source_shell_functions(vcontainer_files_dir, tmp_path):
    """Create a test script that sources the shell functions."""
    # We need to extract specific functions from vcontainer-common.sh
    # for unit testing without running the full script
    test_script = tmp_path / "test_functions.sh"

    # Copy the necessary functions from vcontainer-common.sh
    vcontainer_common = vcontainer_files_dir / "vcontainer-common.sh"
    if not vcontainer_common.exists():
        return None

    # Read and extract the multi-arch functions
    content = vcontainer_common.read_text()

    # Find the multi-arch section
    start_marker = "# Multi-Architecture OCI Support"
    end_marker = "show_usage()"

    start_idx = content.find(start_marker)
    end_idx = content.find(end_marker, start_idx)

    if start_idx == -1 or end_idx == -1:
        return None

    functions = content[start_idx:end_idx]

    test_script.write_text(f"""#!/bin/bash
# Extracted multi-arch functions for testing

{functions}

# Test harness
"$@"
""")
    test_script.chmod(0o755)
    return test_script


class TestOCIImageIndexDetection:
    """Test OCI Image Index detection functions."""

    def test_is_oci_image_index_with_multiarch(self, multiarch_oci_dir, vcontainer_files_dir, tmp_path):
        """Test that is_oci_image_index detects multi-arch OCI."""
        test_script = source_shell_functions(vcontainer_files_dir, tmp_path)
        if test_script is None:
            pytest.skip("Could not extract shell functions")

        result = subprocess.run(
            [str(test_script), "is_oci_image_index", str(multiarch_oci_dir)],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode == 0, f"Expected multi-arch detection to succeed. stderr: {result.stderr}"

    def test_is_oci_image_index_with_single_arch(self, singlearch_oci_dir, vcontainer_files_dir, tmp_path):
        """Test that is_oci_image_index returns false for single-arch OCI."""
        test_script = source_shell_functions(vcontainer_files_dir, tmp_path)
        if test_script is None:
            pytest.skip("Could not extract shell functions")

        result = subprocess.run(
            [str(test_script), "is_oci_image_index", str(singlearch_oci_dir)],
            capture_output=True,
            text=True,
            timeout=10
        )
        # Single-arch without platform info should return non-zero
        assert result.returncode != 0, "Expected single-arch detection to fail"

    def test_is_oci_image_index_missing_file(self, tmp_path, vcontainer_files_dir):
        """Test that is_oci_image_index handles missing index.json."""
        test_script = source_shell_functions(vcontainer_files_dir, tmp_path)
        if test_script is None:
            pytest.skip("Could not extract shell functions")

        empty_dir = tmp_path / "empty-oci"
        empty_dir.mkdir()

        result = subprocess.run(
            [str(test_script), "is_oci_image_index", str(empty_dir)],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode != 0, "Expected missing file detection to fail"


class TestPlatformSelection:
    """Test architecture selection functions."""

    def test_select_platform_manifest_aarch64(self, multiarch_oci_dir, vcontainer_files_dir, tmp_path):
        """Test selecting arm64 manifest for aarch64 target."""
        test_script = source_shell_functions(vcontainer_files_dir, tmp_path)
        if test_script is None:
            pytest.skip("Could not extract shell functions")

        result = subprocess.run(
            [str(test_script), "select_platform_manifest", str(multiarch_oci_dir), "aarch64"],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode == 0, f"Expected platform selection to succeed. stderr: {result.stderr}"
        # Should output a digest
        assert result.stdout.strip(), "Expected digest output"

    def test_select_platform_manifest_x86_64(self, multiarch_oci_dir, vcontainer_files_dir, tmp_path):
        """Test selecting amd64 manifest for x86_64 target."""
        test_script = source_shell_functions(vcontainer_files_dir, tmp_path)
        if test_script is None:
            pytest.skip("Could not extract shell functions")

        result = subprocess.run(
            [str(test_script), "select_platform_manifest", str(multiarch_oci_dir), "x86_64"],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode == 0, f"Expected platform selection to succeed. stderr: {result.stderr}"
        assert result.stdout.strip(), "Expected digest output"

    def test_select_platform_manifest_not_found(self, multiarch_oci_dir, vcontainer_files_dir, tmp_path):
        """Test that selecting missing platform returns error."""
        test_script = source_shell_functions(vcontainer_files_dir, tmp_path)
        if test_script is None:
            pytest.skip("Could not extract shell functions")

        result = subprocess.run(
            [str(test_script), "select_platform_manifest", str(multiarch_oci_dir), "riscv64"],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode != 0 or not result.stdout.strip(), "Expected missing platform to fail"

    def test_arch_normalization_aarch64_to_arm64(self, vcontainer_files_dir, tmp_path):
        """Test that aarch64 normalizes to arm64."""
        test_script = source_shell_functions(vcontainer_files_dir, tmp_path)
        if test_script is None:
            pytest.skip("Could not extract shell functions")

        result = subprocess.run(
            [str(test_script), "normalize_arch_to_oci", "aarch64"],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.stdout.strip() == "arm64"

    def test_arch_normalization_x86_64_to_amd64(self, vcontainer_files_dir, tmp_path):
        """Test that x86_64 normalizes to amd64."""
        test_script = source_shell_functions(vcontainer_files_dir, tmp_path)
        if test_script is None:
            pytest.skip("Could not extract shell functions")

        result = subprocess.run(
            [str(test_script), "normalize_arch_to_oci", "x86_64"],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.stdout.strip() == "amd64"


class TestGetOCIPlatforms:
    """Test platform listing function."""

    def test_get_platforms_multiarch(self, multiarch_oci_dir, vcontainer_files_dir, tmp_path):
        """Test getting available platforms from multi-arch OCI."""
        test_script = source_shell_functions(vcontainer_files_dir, tmp_path)
        if test_script is None:
            pytest.skip("Could not extract shell functions")

        result = subprocess.run(
            [str(test_script), "get_oci_platforms", str(multiarch_oci_dir)],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode == 0
        platforms = result.stdout.strip().split()
        assert "arm64" in platforms
        assert "amd64" in platforms


class TestExtractPlatformOCI:
    """Test single-platform extraction function."""

    def test_extract_platform_creates_valid_oci(self, multiarch_oci_dir, vcontainer_files_dir, tmp_path):
        """Test that extract_platform_oci creates a valid single-arch OCI."""
        test_script = source_shell_functions(vcontainer_files_dir, tmp_path)
        if test_script is None:
            pytest.skip("Could not extract shell functions")

        # First get the arm64 manifest digest
        result = subprocess.run(
            [str(test_script), "select_platform_manifest", str(multiarch_oci_dir), "aarch64"],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode == 0
        manifest_digest = result.stdout.strip()

        # Extract platform to new directory
        extracted_dir = tmp_path / "extracted-oci"
        result = subprocess.run(
            [str(test_script), "extract_platform_oci", str(multiarch_oci_dir), str(extracted_dir), manifest_digest],
            capture_output=True,
            text=True,
            timeout=10
        )
        assert result.returncode == 0, f"Extraction failed: {result.stderr}"

        # Verify extracted OCI structure
        assert (extracted_dir / "index.json").exists()
        assert (extracted_dir / "oci-layout").exists()
        assert (extracted_dir / "blobs" / "sha256").is_dir()

        # Verify index.json has single manifest
        index = json.loads((extracted_dir / "index.json").read_text())
        assert len(index.get("manifests", [])) == 1
        assert index["manifests"][0]["digest"] == f"sha256:{manifest_digest}"


class TestMultiArchOCIClass:
    """Test oci-multiarch.bbclass file."""

    def test_bbclass_exists(self, meta_virt_dir):
        """Test that the oci-multiarch.bbclass file exists."""
        class_file = meta_virt_dir / "classes" / "oci-multiarch.bbclass"
        assert class_file.exists(), f"Class file not found: {class_file}"

    def test_bbclass_has_required_variables(self, meta_virt_dir):
        """Test that oci-multiarch.bbclass defines required variables."""
        class_file = meta_virt_dir / "classes" / "oci-multiarch.bbclass"
        content = class_file.read_text()

        assert "OCI_MULTIARCH_RECIPE" in content
        assert "OCI_MULTIARCH_PLATFORMS" in content
        assert "OCI_MULTIARCH_MC" in content

    def test_bbclass_creates_image_index(self, meta_virt_dir):
        """Test that oci-multiarch.bbclass creates OCI Image Index."""
        class_file = meta_virt_dir / "classes" / "oci-multiarch.bbclass"
        content = class_file.read_text()

        assert "do_create_multiarch_index" in content
        assert "application/vnd.oci.image.index.v1+json" in content


class TestBackwardCompatibility:
    """Test backward compatibility with single-arch OCI images."""

    def test_single_arch_oci_structure(self, singlearch_oci_dir):
        """Verify single-arch OCI has expected structure."""
        assert (singlearch_oci_dir / "index.json").exists()
        assert (singlearch_oci_dir / "oci-layout").exists()

        index = json.loads((singlearch_oci_dir / "index.json").read_text())
        assert "manifests" in index
        assert len(index["manifests"]) == 1
        # Single-arch should NOT have platform in manifest entry
        assert "platform" not in index["manifests"][0]

    def test_single_arch_detection_fails(self, singlearch_oci_dir, vcontainer_files_dir, tmp_path):
        """Test that single-arch OCI is not detected as multi-arch."""
        test_script = source_shell_functions(vcontainer_files_dir, tmp_path)
        if test_script is None:
            pytest.skip("Could not extract shell functions")

        result = subprocess.run(
            [str(test_script), "is_oci_image_index", str(singlearch_oci_dir)],
            capture_output=True,
            text=True,
            timeout=10
        )
        # Should return non-zero (not a multi-arch image index)
        assert result.returncode != 0


class TestVrunnerMultiArch:
    """Test vrunner.sh multi-arch support."""

    def test_vrunner_has_multiarch_functions(self, vcontainer_files_dir):
        """Test that vrunner.sh contains multi-arch functions."""
        vrunner = vcontainer_files_dir / "vrunner.sh"
        assert vrunner.exists()

        content = vrunner.read_text()
        assert "is_oci_image_index" in content
        assert "select_platform_manifest" in content
        assert "extract_platform_oci" in content
        assert "normalize_arch_to_oci" in content

    def test_vrunner_batch_import_handles_multiarch(self, vcontainer_files_dir):
        """Test that vrunner batch import section checks for multi-arch."""
        vrunner = vcontainer_files_dir / "vrunner.sh"
        content = vrunner.read_text()

        # Batch import section should check for multi-arch
        assert "BATCH_IMPORT" in content
        # The multi-arch handling should be in the batch processing loop
        assert "is_oci_image_index" in content


class TestVcontainerCommonMultiArch:
    """Test vcontainer-common.sh multi-arch support."""

    def test_vcontainer_common_has_multiarch_functions(self, vcontainer_files_dir):
        """Test that vcontainer-common.sh contains multi-arch functions."""
        vcontainer_common = vcontainer_files_dir / "vcontainer-common.sh"
        assert vcontainer_common.exists()

        content = vcontainer_common.read_text()
        assert "is_oci_image_index" in content
        assert "select_platform_manifest" in content
        assert "extract_platform_oci" in content
        assert "get_oci_platforms" in content
        assert "normalize_arch_to_oci" in content
        assert "normalize_arch_from_oci" in content

    def test_vimport_handles_multiarch(self, vcontainer_files_dir):
        """Test that vimport section handles multi-arch OCI."""
        vcontainer_common = vcontainer_files_dir / "vcontainer-common.sh"
        content = vcontainer_common.read_text()

        # vimport should detect and handle multi-arch
        assert "vimport)" in content
        # Should have multi-arch detection in OCI handling
        assert "Multi-arch OCI detected" in content or "is_oci_image_index" in content


class TestContainerRegistryMultiArch:
    """Test container registry multi-arch support."""

    def test_registry_script_has_manifest_list_support(self, meta_virt_dir):
        """Test that container-registry-index.bb has manifest list support."""
        registry_bb = meta_virt_dir / "recipes-containers" / "container-registry" / "container-registry-index.bb"
        assert registry_bb.exists()

        content = registry_bb.read_text()
        # Should have manifest list functions
        assert "update_manifest_list" in content
        assert "is_manifest_list" in content
        assert "get_manifest_list" in content
        assert "push_by_digest" in content

    def test_registry_script_always_creates_manifest_lists(self, meta_virt_dir):
        """Test that push always creates manifest lists."""
        registry_bb = meta_virt_dir / "recipes-containers" / "container-registry" / "container-registry-index.bb"
        content = registry_bb.read_text()

        # Should mention manifest lists in push output
        assert "manifest list" in content.lower()

    def test_registry_script_has_multi_directory_support(self, meta_virt_dir):
        """Test that container-registry-index.bb supports multi-directory scanning."""
        registry_bb = meta_virt_dir / "recipes-containers" / "container-registry" / "container-registry-index.bb"
        content = registry_bb.read_text()

        # Should have DEPLOY_DIR_IMAGES variable for multi-arch scanning
        assert "DEPLOY_DIR_IMAGES" in content
        # Should iterate over machine directories
        assert "machine_dir" in content
        # Should show which machine the image is from
        assert "[from $machine_name]" in content or "from $machine_name" in content

    def test_registry_script_supports_push_by_path(self, meta_virt_dir):
        """Test that push command supports direct OCI directory path."""
        registry_bb = meta_virt_dir / "recipes-containers" / "container-registry" / "container-registry-index.bb"
        content = registry_bb.read_text()

        # Should detect if argument is a path to an OCI directory
        assert "index.json" in content
        # Should have direct path mode
        assert "Direct path mode" in content or "Pushing OCI directory" in content

    def test_registry_script_supports_push_by_name(self, meta_virt_dir):
        """Test that push by name scans all machine directories."""
        registry_bb = meta_virt_dir / "recipes-containers" / "container-registry" / "container-registry-index.bb"
        content = registry_bb.read_text()

        # Should support name filter mode
        assert "image_filter" in content
        # Should scan all architectures when pushing by name
        assert "all architectures" in content.lower() or "all archs" in content.lower()

    def test_registry_script_env_var_override(self, meta_virt_dir):
        """Test that DEPLOY_DIR_IMAGES can be overridden via environment."""
        registry_bb = meta_virt_dir / "recipes-containers" / "container-registry" / "container-registry-index.bb"
        content = registry_bb.read_text()

        # Should use environment variable with fallback to baked-in value
        assert "${DEPLOY_DIR_IMAGES:-" in content or "DEPLOY_DIR_IMAGES:-" in content


class TestRegistryMultiArchIntegration:
    """Integration tests for registry multi-arch push (requires registry fixture)."""

    @pytest.fixture
    def mock_deploy_dirs(self, tmp_path, multiarch_oci_dir):
        """Create mock deploy directory structure with multiple machines."""
        deploy_images = tmp_path / "deploy" / "images"

        # Create qemuarm64 machine dir with arm64 OCI
        arm64_dir = deploy_images / "qemuarm64"
        arm64_dir.mkdir(parents=True)
        arm64_oci = arm64_dir / "container-base-latest-oci"
        shutil.copytree(multiarch_oci_dir, arm64_oci)

        # Modify the arm64 OCI to only have arm64 manifest
        arm64_index = json.loads((arm64_oci / "index.json").read_text())
        arm64_index["manifests"] = [m for m in arm64_index["manifests"]
                                    if m.get("platform", {}).get("architecture") == "arm64"]
        (arm64_oci / "index.json").write_text(json.dumps(arm64_index, indent=2))

        # Create qemux86-64 machine dir with amd64 OCI
        amd64_dir = deploy_images / "qemux86-64"
        amd64_dir.mkdir(parents=True)
        amd64_oci = amd64_dir / "container-base-latest-oci"
        shutil.copytree(multiarch_oci_dir, amd64_oci)

        # Modify the amd64 OCI to only have amd64 manifest
        amd64_index = json.loads((amd64_oci / "index.json").read_text())
        amd64_index["manifests"] = [m for m in amd64_index["manifests"]
                                    if m.get("platform", {}).get("architecture") == "amd64"]
        (amd64_oci / "index.json").write_text(json.dumps(amd64_index, indent=2))

        return deploy_images

    def test_mock_deploy_structure(self, mock_deploy_dirs):
        """Verify mock deploy directory structure is correct."""
        assert (mock_deploy_dirs / "qemuarm64" / "container-base-latest-oci" / "index.json").exists()
        assert (mock_deploy_dirs / "qemux86-64" / "container-base-latest-oci" / "index.json").exists()

        # Verify arm64 OCI has arm64 only
        arm64_index = json.loads(
            (mock_deploy_dirs / "qemuarm64" / "container-base-latest-oci" / "index.json").read_text()
        )
        assert len(arm64_index["manifests"]) == 1
        assert arm64_index["manifests"][0]["platform"]["architecture"] == "arm64"

        # Verify amd64 OCI has amd64 only
        amd64_index = json.loads(
            (mock_deploy_dirs / "qemux86-64" / "container-base-latest-oci" / "index.json").read_text()
        )
        assert len(amd64_index["manifests"]) == 1
        assert amd64_index["manifests"][0]["platform"]["architecture"] == "amd64"

    def test_discover_oci_in_multiple_machines(self, mock_deploy_dirs):
        """Test that OCI directories can be discovered in multiple machine dirs."""
        found = []
        for machine_dir in mock_deploy_dirs.iterdir():
            if machine_dir.is_dir():
                for oci_dir in machine_dir.glob("*-oci"):
                    if (oci_dir / "index.json").exists():
                        index = json.loads((oci_dir / "index.json").read_text())
                        arch = index["manifests"][0].get("platform", {}).get("architecture", "unknown")
                        found.append((machine_dir.name, oci_dir.name, arch))

        assert len(found) == 2
        machines = {f[0] for f in found}
        assert "qemuarm64" in machines
        assert "qemux86-64" in machines

        archs = {f[2] for f in found}
        assert "arm64" in archs
        assert "amd64" in archs
