# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Tests for vcontainer distro and multi-arch OCI container build infrastructure.

Verifies:
- vruntime-base.inc shared base exists and has correct content
- vcontainer.conf distro uses shared base without BBMASK
- vruntime.conf uses shared base with BBMASK (no regression)
- Container multiconfig files exist and reference vcontainer distro
- oci-multiarch.bbclass defaults point to container-* multiconfigs
- container-base-multiarch.bb recipe wires up correctly
- meta-virt-host.conf BBMULTICONFIG includes container-* entries
- Built OCI output has valid multi-arch structure (when available)

Run with:
    pytest tests/test_vcontainer_distro.py -v --poky-dir /opt/bruce/poky

Build-dependent tests (marked @pytest.mark.slow) require:
    bitbake container-base-multiarch
"""

import json
import os
import pytest
from pathlib import Path


@pytest.fixture(scope="module")
def meta_virt_dir(request):
    """Path to meta-virtualization layer."""
    poky_dir = Path(request.config.getoption("--poky-dir"))
    path = poky_dir / "meta-virtualization"
    if not path.exists():
        pytest.skip(f"meta-virtualization not found: {path}")
    return path


@pytest.fixture(scope="module")
def build_dir(request):
    """Path to build directory."""
    bd = request.config.getoption("--build-dir")
    if bd:
        return Path(bd)
    poky_dir = Path(request.config.getoption("--poky-dir"))
    return poky_dir / "build"


# =============================================================================
# Tier 1: Static file assertions (no bitbake required)
# =============================================================================

class TestVruntimeBaseInc:
    """Test the shared vruntime-base.inc fragment."""

    def test_exists(self, meta_virt_dir):
        path = meta_virt_dir / "conf" / "distro" / "include" / "vruntime-base.inc"
        assert path.exists(), f"Missing: {path}"

    def test_requires_poky(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "include" / "vruntime-base.inc").read_text()
        assert "require conf/distro/poky.conf" in content

    def test_sets_distro_features(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "include" / "vruntime-base.inc").read_text()
        assert 'DISTRO_FEATURES = "' in content
        assert "vcontainer" in content
        assert "seccomp" in content

    def test_opts_out_features(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "include" / "vruntime-base.inc").read_text()
        assert "DISTRO_FEATURES_OPTED_OUT" in content
        assert "pulseaudio" in content
        assert "wayland" in content

    def test_native_class_overrides(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "include" / "vruntime-base.inc").read_text()
        assert "DISTRO_FEATURES:class-native" in content
        assert "DISTRO_FEATURES:class-nativesdk" in content

    def test_does_not_set_distro_name(self, meta_virt_dir):
        """Shared base must NOT set DISTRO or DISTRO_NAME — consumers do that."""
        content = (meta_virt_dir / "conf" / "distro" / "include" / "vruntime-base.inc").read_text()
        for line in content.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            assert not stripped.startswith("DISTRO ="), "vruntime-base.inc must not set DISTRO"
            assert not stripped.startswith("DISTRO_NAME"), "vruntime-base.inc must not set DISTRO_NAME"

    def test_does_not_include_bbmask(self, meta_virt_dir):
        """Shared base must NOT include BBMASK files."""
        content = (meta_virt_dir / "conf" / "distro" / "include" / "vruntime-base.inc").read_text()
        assert "bbmask" not in content.lower()


class TestVcontainerConf:
    """Test the vcontainer OCI builder distro."""

    def test_exists(self, meta_virt_dir):
        path = meta_virt_dir / "conf" / "distro" / "vcontainer.conf"
        assert path.exists(), f"Missing: {path}"

    def test_requires_shared_base(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "vcontainer.conf").read_text()
        assert "require conf/distro/include/vruntime-base.inc" in content

    def test_sets_distro(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "vcontainer.conf").read_text()
        assert 'DISTRO = "vcontainer"' in content

    def test_has_lighter_bbmask(self, meta_virt_dir):
        """vcontainer uses its own lighter BBMASK, not vruntime's."""
        content = (meta_virt_dir / "conf" / "distro" / "vcontainer.conf").read_text()
        assert "vcontainer-bbmask.inc" in content
        # Must NOT use vruntime's BBMASK (it blocks OCI tooling)
        for line in content.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            assert "vruntime-bbmask.inc" not in stripped, \
                "vcontainer must not use vruntime-bbmask.inc (blocks OCI tooling)"

    def test_no_image_fstypes(self, meta_virt_dir):
        """vcontainer must NOT set IMAGE_FSTYPES -- 'oci' type needs image-oci.bbclass
        which only container recipes inherit. Setting it distro-wide breaks other images."""
        content = (meta_virt_dir / "conf" / "distro" / "vcontainer.conf").read_text()
        for line in content.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            assert not stripped.startswith("IMAGE_FSTYPES"), \
                "IMAGE_FSTYPES must not be set in vcontainer.conf (breaks non-container images)"

    def test_does_not_duplicate_base_settings(self, meta_virt_dir):
        """vcontainer should not re-declare settings already in vruntime-base.inc."""
        content = (meta_virt_dir / "conf" / "distro" / "vcontainer.conf").read_text()
        for line in content.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            assert not stripped.startswith("DISTRO_FEATURES ="), \
                "DISTRO_FEATURES belongs in vruntime-base.inc"
            assert not stripped.startswith("DISTRO_FEATURES_OPTED_OUT"), \
                "DISTRO_FEATURES_OPTED_OUT belongs in vruntime-base.inc"


class TestVcontainerBbmask:
    """Test the vcontainer-bbmask.inc keeps OCI tooling available."""

    def test_exists(self, meta_virt_dir):
        path = meta_virt_dir / "conf" / "distro" / "include" / "vcontainer-bbmask.inc"
        assert path.exists()

    def test_masks_graphics(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "include" / "vcontainer-bbmask.inc").read_text()
        assert "recipes-graphics" in content
        assert "recipes-sato" in content

    def test_masks_virtualization_platforms(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "include" / "vcontainer-bbmask.inc").read_text()
        assert "recipes-extended/xen/" in content
        assert "recipes-extended/libvirt/" in content

    def test_does_not_mask_oci_tooling(self, meta_virt_dir):
        """OCI tooling must NOT be masked — this is the key difference from vruntime."""
        content = (meta_virt_dir / "conf" / "distro" / "include" / "vcontainer-bbmask.inc").read_text()
        # Check non-comment lines for things that must stay unmasked
        for line in content.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            assert "recipes-containers/umoci/" not in stripped, "umoci must not be masked"
            assert "recipes-containers/container-registry/" not in stripped, "container-registry must not be masked"
            assert "recipes-extended/images/" not in stripped, "container image recipes must not be masked"
            assert "recipes-containers/oci-image-tools/" not in stripped, "oci-image-tools must not be masked"
            assert "recipes-containers/sloci-image/" not in stripped, "sloci-image must not be masked"

    def test_masks_orchestration(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "include" / "vcontainer-bbmask.inc").read_text()
        assert "recipes-containers/kubernetes/" in content
        assert "recipes-containers/k3s/" in content


class TestVruntimeConfRefactored:
    """Test that vruntime.conf still works after refactoring."""

    def test_requires_shared_base(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "vruntime.conf").read_text()
        assert "require conf/distro/include/vruntime-base.inc" in content

    def test_still_has_bbmask(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "vruntime.conf").read_text()
        assert "vruntime-bbmask.inc" in content
        assert "vruntime-bbmask-oe-core.inc" in content
        assert "vruntime-bbmask-meta-oe.inc" in content

    def test_sets_distro_vruntime(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "vruntime.conf").read_text()
        assert 'DISTRO = "vruntime"' in content

    def test_no_direct_poky_require(self, meta_virt_dir):
        """vruntime.conf should get poky.conf via vruntime-base.inc, not directly."""
        content = (meta_virt_dir / "conf" / "distro" / "vruntime.conf").read_text()
        for line in content.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            assert "require conf/distro/poky.conf" not in stripped, \
                "vruntime.conf should not directly require poky.conf (it comes via vruntime-base.inc)"

    def test_does_not_duplicate_base_settings(self, meta_virt_dir):
        """vruntime.conf should not re-declare settings already in vruntime-base.inc."""
        content = (meta_virt_dir / "conf" / "distro" / "vruntime.conf").read_text()
        for line in content.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            assert not stripped.startswith("DISTRO_FEATURES ="), \
                "DISTRO_FEATURES belongs in vruntime-base.inc, not vruntime.conf"
            assert not stripped.startswith("DISTRO_FEATURES_OPTED_OUT"), \
                "DISTRO_FEATURES_OPTED_OUT belongs in vruntime-base.inc"

    def test_busybox_init(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "vruntime.conf").read_text()
        assert "busybox" in content

    def test_ptest_glib_disabled(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "vruntime.conf").read_text()
        assert 'PTEST_ENABLED:pn-glib-2.0 = ""' in content


class TestContainerMulticonfigs:
    """Test container multiconfig files."""

    def test_container_aarch64_exists(self, meta_virt_dir):
        path = meta_virt_dir / "conf" / "multiconfig" / "container-aarch64.conf"
        assert path.exists(), f"Missing: {path}"

    def test_container_x86_64_exists(self, meta_virt_dir):
        path = meta_virt_dir / "conf" / "multiconfig" / "container-x86-64.conf"
        assert path.exists(), f"Missing: {path}"

    def test_old_container_conf_removed(self, meta_virt_dir):
        path = meta_virt_dir / "conf" / "multiconfig" / "container.conf"
        assert not path.exists(), f"Stale placeholder should be removed: {path}"

    def test_aarch64_uses_vcontainer(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "multiconfig" / "container-aarch64.conf").read_text()
        assert 'DISTRO = "vcontainer"' in content
        assert 'MACHINE = "qemuarm64"' in content

    def test_x86_64_uses_vcontainer(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "multiconfig" / "container-x86-64.conf").read_text()
        assert 'DISTRO = "vcontainer"' in content
        assert 'MACHINE = "qemux86-64"' in content

    def test_aarch64_has_separate_tmpdir(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "multiconfig" / "container-aarch64.conf").read_text()
        assert "tmp-container-aarch64" in content

    def test_x86_64_has_separate_tmpdir(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "multiconfig" / "container-x86-64.conf").read_text()
        assert "tmp-container-x86-64" in content


class TestOCIMultiarchClassUpdated:
    """Test oci-multiarch.bbclass points to container-* multiconfigs."""

    def test_default_mc_aarch64(self, meta_virt_dir):
        content = (meta_virt_dir / "classes" / "oci-multiarch.bbclass").read_text()
        assert 'OCI_MULTIARCH_MC[aarch64] ?= "container-aarch64"' in content

    def test_default_mc_x86_64(self, meta_virt_dir):
        content = (meta_virt_dir / "classes" / "oci-multiarch.bbclass").read_text()
        assert 'OCI_MULTIARCH_MC[x86_64] ?= "container-x86-64"' in content

    def test_no_vruntime_mc_defaults(self, meta_virt_dir):
        """oci-multiarch defaults must NOT reference vruntime-* (BBMASK blocks OCI tools)."""
        content = (meta_virt_dir / "classes" / "oci-multiarch.bbclass").read_text()
        # Check non-comment lines
        for line in content.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if "OCI_MULTIARCH_MC" in stripped and "?=" in stripped:
                assert "vruntime" not in stripped, \
                    f"OCI MC default must not reference vruntime: {stripped}"


class TestMetaVirtHostConf:
    """Test meta-virt-host.conf includes container multiconfigs."""

    def test_bbmulticonfig_has_container_mcs(self, meta_virt_dir):
        content = (meta_virt_dir / "conf" / "distro" / "include" / "meta-virt-host.conf").read_text()
        assert "container-aarch64" in content
        assert "container-x86-64" in content

    def test_bbmulticonfig_still_has_vruntime(self, meta_virt_dir):
        """Existing vruntime MCs must not be removed."""
        content = (meta_virt_dir / "conf" / "distro" / "include" / "meta-virt-host.conf").read_text()
        assert "vruntime-aarch64" in content
        assert "vruntime-x86-64" in content


class TestContainerBaseMultiarchRecipe:
    """Test container-base-multiarch.bb recipe."""

    def test_exists(self, meta_virt_dir):
        path = meta_virt_dir / "recipes-extended" / "images" / "container-base-multiarch.bb"
        assert path.exists(), f"Missing: {path}"

    def test_inherits_oci_multiarch(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-extended" / "images" / "container-base-multiarch.bb").read_text()
        assert "inherit oci-multiarch" in content

    def test_recipe_target(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-extended" / "images" / "container-base-multiarch.bb").read_text()
        assert 'OCI_MULTIARCH_RECIPE = "container-base"' in content

    def test_platforms(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-extended" / "images" / "container-base-multiarch.bb").read_text()
        assert "aarch64" in content
        assert "x86_64" in content

    def test_has_license(self, meta_virt_dir):
        content = (meta_virt_dir / "recipes-extended" / "images" / "container-base-multiarch.bb").read_text()
        assert "LICENSE" in content


# =============================================================================
# Tier 2: Consistency checks across files
# =============================================================================

class TestCrossFileConsistency:
    """Verify that the distro/multiconfig/bbclass files are consistent."""

    def test_vcontainer_and_vruntime_share_same_base(self, meta_virt_dir):
        """Both distros must require the same shared base."""
        vruntime = (meta_virt_dir / "conf" / "distro" / "vruntime.conf").read_text()
        vcontainer = (meta_virt_dir / "conf" / "distro" / "vcontainer.conf").read_text()
        base_require = "require conf/distro/include/vruntime-base.inc"
        assert base_require in vruntime
        assert base_require in vcontainer

    def test_multiconfig_distro_matches_conf(self, meta_virt_dir):
        """Multiconfig DISTRO must match vcontainer.conf's DISTRO."""
        vcontainer = (meta_virt_dir / "conf" / "distro" / "vcontainer.conf").read_text()
        mc_arm = (meta_virt_dir / "conf" / "multiconfig" / "container-aarch64.conf").read_text()
        mc_x86 = (meta_virt_dir / "conf" / "multiconfig" / "container-x86-64.conf").read_text()
        assert 'DISTRO = "vcontainer"' in vcontainer
        assert 'DISTRO = "vcontainer"' in mc_arm
        assert 'DISTRO = "vcontainer"' in mc_x86

    def test_bbclass_mc_names_match_multiconfig_files(self, meta_virt_dir):
        """oci-multiarch.bbclass MC names must have matching multiconfig/*.conf files."""
        content = (meta_virt_dir / "classes" / "oci-multiarch.bbclass").read_text()
        mc_dir = meta_virt_dir / "conf" / "multiconfig"

        # Extract default MC names from ?= lines
        for line in content.splitlines():
            if "OCI_MULTIARCH_MC" in line and "?=" in line:
                # Parse: OCI_MULTIARCH_MC[arch] ?= "mc-name"
                mc_name = line.split('"')[1] if '"' in line else None
                if mc_name:
                    mc_file = mc_dir / f"{mc_name}.conf"
                    assert mc_file.exists(), \
                        f"bbclass references MC '{mc_name}' but {mc_file} missing"

    def test_bbclass_machines_match_multiconfig(self, meta_virt_dir):
        """oci-multiarch.bbclass machine names must match multiconfig MACHINE values."""
        bbclass = (meta_virt_dir / "classes" / "oci-multiarch.bbclass").read_text()

        # Extract machine mapping from bbclass
        machine_map = {}
        for line in bbclass.splitlines():
            if "OCI_MULTIARCH_MACHINE" in line and "?=" in line:
                # OCI_MULTIARCH_MACHINE[aarch64] ?= "qemuarm64"
                if "[" in line and "]" in line:
                    arch = line.split("[")[1].split("]")[0]
                    machine = line.split('"')[1]
                    machine_map[arch] = machine

        # Extract MC mapping from bbclass
        mc_map = {}
        for line in bbclass.splitlines():
            if "OCI_MULTIARCH_MC" in line and "?=" in line:
                if "[" in line and "]" in line:
                    arch = line.split("[")[1].split("]")[0]
                    mc = line.split('"')[1]
                    mc_map[arch] = mc

        # Verify each MC's MACHINE matches the bbclass machine mapping
        mc_dir = meta_virt_dir / "conf" / "multiconfig"
        for arch, mc_name in mc_map.items():
            mc_file = mc_dir / f"{mc_name}.conf"
            if mc_file.exists() and arch in machine_map:
                mc_content = mc_file.read_text()
                expected_machine = machine_map[arch]
                assert f'MACHINE = "{expected_machine}"' in mc_content, \
                    f"MC {mc_name} MACHINE should be {expected_machine}"


# =============================================================================
# Tier 3: Build output verification (requires bitbake)
# =============================================================================

@pytest.mark.slow
class TestMultiArchBuildOutput:
    """Verify OCI output from bitbake container-base-multiarch.

    These tests require a prior build:
        bitbake container-base-multiarch
    """

    @pytest.fixture(scope="class")
    def multiarch_output(self, build_dir):
        """Find the multi-arch OCI output directory."""
        # oci-multiarch.bbclass puts output in DEPLOY_DIR_IMAGE
        # Try the main build's deploy dir first
        candidates = [
            build_dir / "tmp" / "deploy" / "images",
        ]
        # Also check machine-specific dirs
        for candidate in candidates:
            if candidate.exists():
                for d in candidate.rglob("*-multiarch-oci"):
                    if (d / "index.json").exists():
                        return d
        pytest.skip("Multi-arch OCI output not found — run: bitbake container-base-multiarch")

    def test_index_json_exists(self, multiarch_output):
        assert (multiarch_output / "index.json").exists()

    def test_oci_layout_exists(self, multiarch_output):
        assert (multiarch_output / "oci-layout").exists()
        layout = json.loads((multiarch_output / "oci-layout").read_text())
        assert layout.get("imageLayoutVersion") == "1.0.0"

    def test_blobs_directory_exists(self, multiarch_output):
        assert (multiarch_output / "blobs" / "sha256").is_dir()

    def test_index_is_oci_image_index(self, multiarch_output):
        index = json.loads((multiarch_output / "index.json").read_text())
        assert index.get("schemaVersion") == 2
        assert index.get("mediaType") == "application/vnd.oci.image.index.v1+json"

    def test_has_arm64_platform(self, multiarch_output):
        index = json.loads((multiarch_output / "index.json").read_text())
        platforms = [m.get("platform", {}).get("architecture")
                     for m in index.get("manifests", [])]
        assert "arm64" in platforms, f"arm64 not in platforms: {platforms}"

    def test_has_amd64_platform(self, multiarch_output):
        index = json.loads((multiarch_output / "index.json").read_text())
        platforms = [m.get("platform", {}).get("architecture")
                     for m in index.get("manifests", [])]
        assert "amd64" in platforms, f"amd64 not in platforms: {platforms}"

    def test_all_manifests_have_os_linux(self, multiarch_output):
        index = json.loads((multiarch_output / "index.json").read_text())
        for m in index.get("manifests", []):
            assert m.get("platform", {}).get("os") == "linux"

    def test_manifest_blobs_exist(self, multiarch_output):
        """Every manifest digest must have a matching blob."""
        index = json.loads((multiarch_output / "index.json").read_text())
        blobs_dir = multiarch_output / "blobs" / "sha256"
        for m in index.get("manifests", []):
            digest = m["digest"]
            assert digest.startswith("sha256:")
            blob_hash = digest[len("sha256:"):]
            assert (blobs_dir / blob_hash).exists(), \
                f"Missing blob for manifest: {digest}"

    def test_manifest_sizes_match(self, multiarch_output):
        """Manifest size in index must match actual blob size."""
        index = json.loads((multiarch_output / "index.json").read_text())
        blobs_dir = multiarch_output / "blobs" / "sha256"
        for m in index.get("manifests", []):
            blob_hash = m["digest"][len("sha256:"):]
            blob_path = blobs_dir / blob_hash
            if blob_path.exists():
                actual_size = blob_path.stat().st_size
                assert actual_size == m["size"], \
                    f"Size mismatch for {m['digest']}: index={m['size']} actual={actual_size}"

    def test_each_manifest_is_valid_json(self, multiarch_output):
        """Each manifest blob must be valid JSON with expected OCI fields."""
        index = json.loads((multiarch_output / "index.json").read_text())
        blobs_dir = multiarch_output / "blobs" / "sha256"
        for m in index.get("manifests", []):
            blob_hash = m["digest"][len("sha256:"):]
            blob_path = blobs_dir / blob_hash
            if blob_path.exists():
                manifest = json.loads(blob_path.read_text())
                assert manifest.get("schemaVersion") == 2
                assert "config" in manifest
                assert "layers" in manifest


@pytest.mark.slow
class TestSingleArchContainerBuild:
    """Verify single-arch container OCI output.

    Requires: bitbake mc:container-x86-64:container-base
    """

    @pytest.fixture(scope="class")
    def x86_oci_dir(self, build_dir):
        """Find x86-64 container OCI output."""
        deploy = build_dir / "tmp-container-x86-64" / "deploy" / "images" / "qemux86-64"
        if not deploy.exists():
            pytest.skip("x86-64 container build not found — run: bitbake mc:container-x86-64:container-base")
        for d in deploy.glob("container-base*oci"):
            if (d / "index.json").exists():
                return d
        pytest.skip("container-base OCI output not found in deploy dir")

    def test_index_json_valid(self, x86_oci_dir):
        index = json.loads((x86_oci_dir / "index.json").read_text())
        assert "manifests" in index
        assert len(index["manifests"]) >= 1

    def test_has_oci_layout(self, x86_oci_dir):
        assert (x86_oci_dir / "oci-layout").exists()

    def test_has_blobs(self, x86_oci_dir):
        blobs = x86_oci_dir / "blobs" / "sha256"
        assert blobs.is_dir()
        assert len(list(blobs.iterdir())) > 0, "No blobs found"
