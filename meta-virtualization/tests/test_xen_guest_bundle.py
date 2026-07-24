# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Tests for xen-guest-bundle.bbclass - Xen guest bundling system.

These tests verify:
  - bbclass file structure and syntax
  - Import handler definitions
  - Parse-time logic (__anonymous)
  - Alpine example recipe structure
  - Build tests (slow, require configured build environment)

Run with:
    pytest tests/test_xen_guest_bundle.py -v

Run build tests (requires configured Yocto build):
    pytest tests/test_xen_guest_bundle.py -v -m slow --machine qemuarm64

Environment variables:
    POKY_DIR: Path to poky directory (default: /opt/bruce/poky)
    BUILD_DIR: Path to build directory (default: $POKY_DIR/build)
    MACHINE: Target machine (default: qemux86-64)
"""

import re
import pytest
from pathlib import Path


# Note: Command line options (--poky-dir, --build-dir, --machine)
# are defined in conftest.py


@pytest.fixture(scope="module")
def poky_dir(request):
    """Path to poky directory."""
    path = Path(request.config.getoption("--poky-dir"))
    if not path.exists():
        pytest.skip(f"Poky directory not found: {path}")
    return path


@pytest.fixture(scope="module")
def meta_virt_dir(poky_dir):
    """Path to meta-virtualization layer."""
    path = poky_dir / "meta-virtualization"
    if not path.exists():
        pytest.skip(f"meta-virtualization not found: {path}")
    return path


@pytest.fixture(scope="module")
def bbclass_content(meta_virt_dir):
    """Content of xen-guest-bundle.bbclass."""
    path = meta_virt_dir / "classes" / "xen-guest-bundle.bbclass"
    if not path.exists():
        pytest.skip(f"bbclass not found: {path}")
    return path.read_text()


@pytest.fixture(scope="module")
def alpine_recipe_content(meta_virt_dir):
    """Content of alpine-xen-guest-bundle recipe."""
    recipes = list((meta_virt_dir / "recipes-extended" / "xen-guest-bundles").glob(
        "alpine-xen-guest-bundle_*.bb"))
    if not recipes:
        pytest.skip("Alpine guest bundle recipe not found")
    return recipes[0].read_text()


# ============================================================================
# bbclass structure tests
# ============================================================================

class TestXenGuestBundleClass:
    """Test xen-guest-bundle.bbclass structure and syntax."""

    def test_class_exists(self, meta_virt_dir):
        """Test that the bbclass file exists."""
        path = meta_virt_dir / "classes" / "xen-guest-bundle.bbclass"
        assert path.exists(), f"bbclass not found: {path}"

    def test_spdx_header(self, bbclass_content):
        """Test SPDX license header is present."""
        assert "SPDX-License-Identifier: MIT" in bbclass_content

    def test_default_variables(self, bbclass_content):
        """Test that expected default variables are defined."""
        defaults = [
            "XEN_GUEST_BUNDLES",
            "XEN_GUEST_IMAGE_FSTYPE",
            "XEN_GUEST_MEMORY_DEFAULT",
            "XEN_GUEST_VCPUS_DEFAULT",
            "XEN_GUEST_VIF_DEFAULT",
            "XEN_GUEST_EXTRA_DEFAULT",
            "XEN_GUEST_DISK_DEVICE_DEFAULT",
        ]
        for var in defaults:
            assert var in bbclass_content, f"Default variable {var} not found"

    def test_anonymous_function(self, bbclass_content):
        """Test that __anonymous() is defined."""
        assert "python __anonymous()" in bbclass_content

    def test_do_compile_defined(self, bbclass_content):
        """Test that do_compile is defined."""
        assert "do_compile()" in bbclass_content

    def test_do_install_defined(self, bbclass_content):
        """Test that do_install is defined."""
        assert "do_install()" in bbclass_content

    def test_resolve_bundle_rootfs(self, bbclass_content):
        """Test rootfs resolver function exists."""
        assert "resolve_bundle_rootfs()" in bbclass_content

    def test_resolve_bundle_kernel(self, bbclass_content):
        """Test kernel resolver function exists."""
        assert "resolve_bundle_kernel()" in bbclass_content

    def test_generate_bundle_config(self, bbclass_content):
        """Test config generator function exists."""
        assert "generate_bundle_config()" in bbclass_content

    def test_files_variable(self, bbclass_content):
        """Test FILES variable is set."""
        assert "FILES:${PN}" in bbclass_content
        assert "xen-guest-bundles" in bbclass_content

    def test_insane_skip(self, bbclass_content):
        """Test INSANE_SKIP for binary images."""
        assert "INSANE_SKIP" in bbclass_content
        assert "buildpaths" in bbclass_content


# ============================================================================
# Import system tests
# ============================================================================

class TestImportSystem:
    """Test import system for 3rd-party guests."""

    def test_import_default_variables(self, bbclass_content):
        """Test import-related default variables."""
        assert "XEN_GUEST_IMAGE_SIZE_DEFAULT" in bbclass_content
        assert "XEN_GUEST_IMPORT_DEPENDS_rootfs_dir" in bbclass_content
        assert "XEN_GUEST_IMPORT_DEPENDS_qcow2" in bbclass_content
        assert "XEN_GUEST_IMPORT_DEPENDS_ext4" in bbclass_content
        assert "XEN_GUEST_IMPORT_DEPENDS_raw" in bbclass_content

    def test_import_depends_rootfs_dir(self, bbclass_content):
        """Test rootfs_dir depends on e2fsprogs-native."""
        match = re.search(
            r'XEN_GUEST_IMPORT_DEPENDS_rootfs_dir\s*=\s*"([^"]*)"',
            bbclass_content)
        assert match, "rootfs_dir depends not found"
        assert "e2fsprogs-native" in match.group(1)

    def test_import_depends_qcow2(self, bbclass_content):
        """Test qcow2 depends on qemu-system-native."""
        match = re.search(
            r'XEN_GUEST_IMPORT_DEPENDS_qcow2\s*=\s*"([^"]*)"',
            bbclass_content)
        assert match, "qcow2 depends not found"
        assert "qemu-system-native" in match.group(1)

    def test_import_handler_rootfs_dir(self, bbclass_content):
        """Test rootfs_dir import handler exists."""
        assert "xen_guest_import_rootfs_dir()" in bbclass_content
        assert "mkfs.ext4" in bbclass_content

    def test_import_handler_qcow2(self, bbclass_content):
        """Test qcow2 import handler exists."""
        assert "xen_guest_import_qcow2()" in bbclass_content
        assert "qemu-img convert" in bbclass_content

    def test_import_handler_ext4(self, bbclass_content):
        """Test ext4 import handler exists."""
        assert "xen_guest_import_ext4()" in bbclass_content

    def test_import_handler_raw(self, bbclass_content):
        """Test raw import handler exists."""
        assert "xen_guest_import_raw()" in bbclass_content

    def test_resolve_import_source(self, bbclass_content):
        """Test import source resolver exists."""
        assert "resolve_import_source()" in bbclass_content
        assert "_XEN_GUEST_IMPORT_MAP" in bbclass_content

    def test_static_dispatch_in_do_compile(self, bbclass_content):
        """Test that import dispatch uses static case statement."""
        # BitBake needs static function references to include them
        assert "case \"$import_type\" in" in bbclass_content
        assert "xen_guest_import_rootfs_dir " in bbclass_content
        assert "xen_guest_import_qcow2 " in bbclass_content

    def test_fakeroot_for_rootfs_dir(self, bbclass_content):
        """Test that rootfs_dir type triggers fakeroot."""
        assert "fakeroot" in bbclass_content
        assert "rootfs_dir" in bbclass_content


# ============================================================================
# Kernel mode tests
# ============================================================================

class TestKernelModes:
    """Test three kernel modes: shared, custom, HVM/none."""

    def test_hvm_mode_documented(self, bbclass_content):
        """Test HVM mode (kernel=none) is supported."""
        assert '"none"' in bbclass_content or "'none'" in bbclass_content
        assert "HVM" in bbclass_content

    def test_kernel_unpackdir_check(self, bbclass_content):
        """Test kernel resolver checks UNPACKDIR."""
        assert "UNPACKDIR" in bbclass_content

    def test_config_omits_kernel_for_hvm(self, bbclass_content):
        """Test generate_bundle_config omits kernel for HVM."""
        # Should have conditional kernel output
        assert 'if [ -n "$kernel_basename" ]' in bbclass_content

    def test_shared_kernel_dependency(self, bbclass_content):
        """Test virtual/kernel dependency for shared kernel."""
        assert "virtual/kernel:do_deploy" in bbclass_content


# ============================================================================
# License warning tests
# ============================================================================

class TestLicenseWarning:
    """Test external guest license warning."""

    def test_external_names_variable(self, bbclass_content):
        """Test _XEN_GUEST_EXTERNAL_NAMES is set for external guests."""
        assert "_XEN_GUEST_EXTERNAL_NAMES" in bbclass_content

    def test_license_warn_prefunc(self, bbclass_content):
        """Test license warning is a prefunc on do_compile."""
        assert "xen_guest_external_license_warn" in bbclass_content
        assert "do_compile[prefuncs]" in bbclass_content

    def test_license_warn_content(self, bbclass_content):
        """Test license warning message content."""
        assert "rights to redistribute" in bbclass_content
        assert "license terms" in bbclass_content

    def test_license_warn_is_python(self, bbclass_content):
        """Test license warning is a python function (runs once at task time)."""
        assert "python xen_guest_external_license_warn()" in bbclass_content


# ============================================================================
# Alpine recipe tests
# ============================================================================

class TestAlpineRecipe:
    """Test alpine-xen-guest-bundle recipe structure."""

    def test_recipe_exists(self, meta_virt_dir):
        """Test that Alpine recipe exists."""
        recipes = list((meta_virt_dir / "recipes-extended" / "xen-guest-bundles").glob(
            "alpine-xen-guest-bundle_*.bb"))
        assert len(recipes) > 0, "Alpine guest bundle recipe not found"

    def test_inherits_xen_guest_bundle(self, alpine_recipe_content):
        """Test recipe inherits xen-guest-bundle."""
        assert "inherit xen-guest-bundle" in alpine_recipe_content

    def test_license(self, alpine_recipe_content):
        """Test recipe has license."""
        assert 'LICENSE = "MIT"' in alpine_recipe_content
        assert "LIC_FILES_CHKSUM" in alpine_recipe_content

    def test_src_uri(self, alpine_recipe_content):
        """Test SRC_URI fetches Alpine minirootfs."""
        assert "dl-cdn.alpinelinux.org" in alpine_recipe_content
        assert "alpine-minirootfs" in alpine_recipe_content
        assert "subdir=alpine-rootfs" in alpine_recipe_content

    def test_per_arch_checksums(self, alpine_recipe_content):
        """Test per-architecture sha256sums are set."""
        aarch64_match = re.search(
            r'SRC_URI\[aarch64\.sha256sum\]\s*=\s*"([^"]*)"',
            alpine_recipe_content)
        x86_64_match = re.search(
            r'SRC_URI\[x86_64\.sha256sum\]\s*=\s*"([^"]*)"',
            alpine_recipe_content)
        assert aarch64_match, "aarch64 sha256sum not found"
        assert x86_64_match, "x86_64 sha256sum not found"
        for name, match in [("aarch64", aarch64_match), ("x86_64", x86_64_match)]:
            sha = match.group(1)
            assert len(sha) == 64, f"{name} sha256sum wrong length: {len(sha)}"
            assert sha != "x" * 64, f"{name} sha256sum is still placeholder"
        # Checksums must differ (different arch tarballs)
        assert aarch64_match.group(1) != x86_64_match.group(1), \
            "aarch64 and x86_64 checksums should differ"

    def test_src_uri_per_arch_name(self, alpine_recipe_content):
        """Test SRC_URI uses name= for per-arch checksum matching."""
        assert "name=${ALPINE_ARCH}" in alpine_recipe_content, \
            "SRC_URI should use name=${ALPINE_ARCH} for per-arch checksums"

    def test_s_variable(self, alpine_recipe_content):
        """Test S variable is set to avoid UNPACKDIR warning."""
        assert 'S = "${UNPACKDIR}"' in alpine_recipe_content

    def test_guest_bundles(self, alpine_recipe_content):
        """Test XEN_GUEST_BUNDLES is set."""
        assert 'XEN_GUEST_BUNDLES = "alpine:autostart:external"' in alpine_recipe_content

    def test_import_source_type(self, alpine_recipe_content):
        """Test import source type is rootfs_dir."""
        assert 'XEN_GUEST_SOURCE_TYPE[alpine] = "rootfs_dir"' in alpine_recipe_content

    def test_import_source_file(self, alpine_recipe_content):
        """Test import source file matches SRC_URI subdir."""
        assert 'XEN_GUEST_SOURCE_FILE[alpine] = "alpine-rootfs"' in alpine_recipe_content

    def test_image_size(self, alpine_recipe_content):
        """Test image size is set."""
        assert 'XEN_GUEST_IMAGE_SIZE[alpine]' in alpine_recipe_content

    def test_guest_memory(self, alpine_recipe_content):
        """Test guest memory is set."""
        assert 'XEN_GUEST_MEMORY[alpine]' in alpine_recipe_content

    def test_guest_extra(self, alpine_recipe_content):
        """Test guest extra args include console."""
        assert 'XEN_GUEST_EXTRA[alpine]' in alpine_recipe_content
        assert "console=hvc0" in alpine_recipe_content

    def test_multiarch_support(self, alpine_recipe_content):
        """Test recipe supports multiple architectures."""
        assert "ALPINE_ARCH" in alpine_recipe_content
        assert "aarch64" in alpine_recipe_content
        assert "x86_64" in alpine_recipe_content


# ============================================================================
# README tests
# ============================================================================

class TestReadme:
    """Test README-xen.md documentation."""

    @pytest.fixture(scope="class")
    def readme_content(self, meta_virt_dir):
        path = meta_virt_dir / "recipes-extended" / "images" / "README-xen.md"
        if not path.exists():
            pytest.skip("README-xen.md not found")
        return path.read_text()

    def test_import_section_exists(self, readme_content):
        """Test 3rd-party import section exists."""
        assert "3rd-party guest import" in readme_content

    def test_import_types_documented(self, readme_content):
        """Test import types are documented."""
        assert "rootfs_dir" in readme_content
        assert "qcow2" in readme_content

    def test_kernel_modes_documented(self, readme_content):
        """Test kernel modes are documented."""
        assert "none" in readme_content
        assert "Shared host kernel" in readme_content or "shared" in readme_content.lower()

    def test_alpine_example(self, readme_content):
        """Test Alpine example is in README."""
        assert "alpine" in readme_content.lower()
        assert "XEN_GUEST_SOURCE_TYPE" in readme_content

    def test_custom_handler_docs(self, readme_content):
        """Test custom handler instructions."""
        assert "xen_guest_import_" in readme_content
        assert "XEN_GUEST_IMPORT_DEPENDS_" in readme_content


# ============================================================================
# x86-64 configuration tests
# ============================================================================

class TestXenImageMinimalX86Config:
    """Test xen-image-minimal.bb x86-64 configuration.

    These verify the fixes needed for Xen on qemux86-64:
    - CPU passthrough to avoid AVX stripping by Xen CPUID filtering
    - Memory configuration using QB_MEM_VALUE (not QB_MEM)
    - dom0_mem in QB_XEN_CMDLINE_EXTRA for runqemu
    - dom0_mem in static WKS syslinux config for guest autostart
    - vgabios using reliable download mirror
    """

    @pytest.fixture(scope="class")
    def image_recipe_content(self, meta_virt_dir):
        path = meta_virt_dir / "recipes-extended" / "images" / "xen-image-minimal.bb"
        if not path.exists():
            pytest.skip("xen-image-minimal.bb not found")
        return path.read_text()

    @pytest.fixture(scope="class")
    def wks_cfg_content(self, meta_virt_dir):
        path = meta_virt_dir / "wic" / "qemuboot-xen-x86-64.cfg"
        if not path.exists():
            pytest.skip("qemuboot-xen-x86-64.cfg not found")
        return path.read_text()

    @pytest.fixture(scope="class")
    def vgabios_recipe_content(self, meta_virt_dir):
        recipes = list((meta_virt_dir / "recipes-extended" / "vgabios").glob(
            "vgabios_*.bb"))
        if not recipes:
            pytest.skip("vgabios recipe not found")
        return recipes[0].read_text()

    def test_cpu_kvm_host_passthrough(self, image_recipe_content):
        """Test QB_CPU_KVM uses -cpu host for qemux86-64.

        Xen's CPUID filtering strips AVX/AVX2 when using fixed CPU models
        (e.g. Skylake-Client), causing illegal instruction crashes with
        x86-64-v3 tune. -cpu host passes real features through KVM.
        """
        assert 'QB_CPU_KVM:qemux86-64 = "-cpu host' in image_recipe_content

    def test_qb_mem_value_not_qb_mem(self, image_recipe_content):
        """Test memory uses QB_MEM_VALUE, not QB_MEM.

        qemuboot-xen-defaults.bbclass uses a hard assign:
          QB_MEM = "-m ${QB_MEM_VALUE}"
        A recipe-level QB_MEM ?= cannot override it. QB_MEM_VALUE ??=
        in the class is the intended override point.
        """
        assert 'QB_MEM_VALUE' in image_recipe_content
        # Should NOT have QB_MEM ?= (common mistake)
        assert 'QB_MEM ?=' not in image_recipe_content

    def test_dom0_mem_in_xen_cmdline(self, image_recipe_content):
        """Test dom0_mem is in QB_XEN_CMDLINE_EXTRA for runqemu."""
        match = re.search(
            r'QB_XEN_CMDLINE_EXTRA\s*=\s*"([^"]*)"', image_recipe_content)
        assert match, "QB_XEN_CMDLINE_EXTRA not found"
        assert "dom0_mem=" in match.group(1), \
            "dom0_mem= must be in QB_XEN_CMDLINE_EXTRA"

    def test_dom0_mem_in_wks_syslinux(self, wks_cfg_content):
        """Test dom0_mem is in static WKS syslinux config.

        Without dom0_mem in the syslinux config, Xen gives ALL memory
        to Dom0 and guest autostart fails with 'failed to free memory'.
        QB_XEN_CMDLINE_EXTRA only affects runqemu's dynamic command line.
        """
        assert "dom0_mem=" in wks_cfg_content, \
            "dom0_mem= must be in qemuboot-xen-x86-64.cfg for guest autostart"

    def test_wks_xen_kernel_cmdline(self, wks_cfg_content):
        """Test WKS config has correct Xen and kernel boot params."""
        assert "mboot.c32" in wks_cfg_content
        assert "/xen.gz" in wks_cfg_content
        assert "console=hvc0" in wks_cfg_content

    def test_vgabios_savannah_mirror(self, vgabios_recipe_content):
        """Test vgabios uses ${SAVANNAH_GNU_MIRROR} for reliable downloads.

        The old http://savannah.gnu.org/download/ URL can redirect to
        broken mirrors that return HTML instead of the tarball.
        """
        assert "${SAVANNAH_GNU_MIRROR}" in vgabios_recipe_content, \
            "vgabios should use ${SAVANNAH_GNU_MIRROR} variable"
        # Should NOT use raw savannah.gnu.org URL
        assert "http://savannah.gnu.org/download" not in vgabios_recipe_content, \
            "Should not use raw savannah.gnu.org URL (broken redirects)"
