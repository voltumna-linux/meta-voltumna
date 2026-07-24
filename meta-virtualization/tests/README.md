# Tests for vdkr, vpdmn, container-cross-install and Xen runtime

Pytest-based test suite for:
- **vdkr**: Docker CLI for cross-architecture emulation
- **vpdmn**: Podman CLI for cross-architecture emulation
- **container-cross-install**: Yocto container bundling system
- **xen-runtime**: Xen hypervisor boot and runtime verification

## Requirements

```bash
pip install pytest pytest-timeout pexpect
```

- `pytest` - Test framework
- `pytest-timeout` - Test timeout handling
- `pexpect` - Required for boot tests (QEMU console interaction)

---

## vdkr Tests

### Prerequisites

Before running vdkr tests, you must build the standalone tarball:

```bash
# 1. Set up your Yocto build environment
cd /opt/bruce/poky
source oe-init-build-env

# 2. Ensure multiconfig is enabled in conf/local.conf:
#    BBMULTICONFIG = "vruntime-aarch64 vruntime-x86-64"

# 3. Build the standalone SDK tarball (includes blobs + QEMU)
MACHINE=qemux86-64 bitbake vcontainer-tarball
# Output: tmp/deploy/sdk/vcontainer-standalone.sh

# 4. Extract the tarball (self-extracting installer)
/opt/bruce/poky/build/tmp/deploy/sdk/vcontainer-standalone.sh -d /tmp/vcontainer -y

# 5. Set up the environment
cd /tmp/vcontainer
source init-env.sh
```

### Running vdkr Tests

Tests use a separate state directory (`~/.vdkr-test/`) to avoid interfering with your production images in `~/.vdkr/`.

```bash
# Run all vdkr tests
cd /opt/bruce/poky/meta-virtualization
pytest tests/test_vdkr.py -v --vdkr-dir /tmp/vcontainer

# Run with memres pre-started (much faster - starts once, reuses for all tests)
./tests/memres-test.sh start --vdkr-dir /tmp/vcontainer
pytest tests/test_vdkr.py -v --vdkr-dir /tmp/vcontainer --skip-destructive
./tests/memres-test.sh stop --vdkr-dir /tmp/vcontainer

# Run only fast tests (skip network/slow tests)
pytest tests/test_vdkr.py -v -m "not slow and not network" --vdkr-dir /tmp/vcontainer

# Run specific test class
pytest tests/test_vdkr.py::TestMemresBasic -v --vdkr-dir /tmp/vcontainer

# Run with an OCI image for import tests
pytest tests/test_vdkr.py -v --vdkr-dir /tmp/vcontainer \
    --oci-image /opt/bruce/poky/build/tmp/deploy/images/qemux86-64/my-container-oci
```

### vdkr Test Options

| Option | Description |
|--------|-------------|
| `--vdkr-dir PATH` | Path to extracted vdkr standalone directory (required) |
| `--arch ARCH` | Target architecture: x86_64 or aarch64 (default: x86_64) |
| `--skip-destructive` | Skip tests that stop memres or clean state (use when memres is pre-started) |
| `--oci-image PATH` | Path to OCI image directory for import tests |

### Testing ARM64 Architecture

When testing ARM64 containers (e.g., after building with `MACHINE=qemuarm64`):

```bash
# Run tests for aarch64
pytest tests/test_vdkr.py tests/test_vpdmn.py -v \
    --vdkr-dir /tmp/vcontainer \
    --arch aarch64 \
    --oci-image /opt/bruce/poky/build/tmp/deploy/images/qemuarm64/container-app-base-latest-oci
```

**Important**: The `--arch` flag must match the OCI image architecture. An arm64 OCI image
requires `--arch aarch64`, and an x86_64 OCI image requires `--arch x86_64` (the default).

---

## vpdmn Tests

vpdmn tests mirror the vdkr tests but for Podman. They use a separate state directory (`~/.vpdmn-test/`).

### Running vpdmn Tests

```bash
# Run all vpdmn tests
cd /opt/bruce/poky/meta-virtualization
pytest tests/test_vpdmn.py -v --vdkr-dir /tmp/vcontainer

# Run with memres pre-started (much faster)
./tests/memres-test.sh start --vdkr-dir /tmp/vcontainer --tool vpdmn
pytest tests/test_vpdmn.py -v --vdkr-dir /tmp/vcontainer --skip-destructive
./tests/memres-test.sh stop --vdkr-dir /tmp/vcontainer --tool vpdmn

# Run only fast tests (skip network/slow tests)
pytest tests/test_vpdmn.py -v -m "not slow and not network" --vdkr-dir /tmp/vcontainer

# Run specific test class
pytest tests/test_vpdmn.py::TestVrun -v --vdkr-dir /tmp/vcontainer
```

### Running Both vdkr and vpdmn Tests

```bash
# Run all tests for both tools
pytest tests/test_vdkr.py tests/test_vpdmn.py -v --vdkr-dir /tmp/vcontainer

# Skip slow and network tests
pytest tests/test_vdkr.py tests/test_vpdmn.py -v -m "not slow and not network" --vdkr-dir /tmp/vcontainer
```

---

## container-cross-install Tests

### Prerequisites

container-cross-install tests require a fully configured Yocto build environment:

```bash
# 1. Set up your Yocto build environment
cd /opt/bruce/poky
source oe-init-build-env

# 2. Ensure required layers are present:
#    - meta-virtualization
#    - meta-oe (openembedded-core)

# 3. Enable multiconfig in conf/local.conf:
BBMULTICONFIG = "vruntime-aarch64 vruntime-x86-64"

# 4. (Optional) Build vdkr/vpdmn blobs via multiconfig if testing container bundling:
#    These are built automatically via mcdepends when building images that
#    inherit container-cross-install or container-bundle.
```

### What the Tests Check

| Test Class | What It Tests | Build Required |
|------------|---------------|----------------|
| `TestContainerCrossClass` | bbclass file syntax | None (file check only) |
| `TestOCIImageBuild` | OCI image generation | `bitbake container-app-base` (if available) |
| `TestBundledContainers` | End-to-end bundling | Full image build with `BUNDLED_CONTAINERS` |
| `TestVdkrRecipes` | vdkr recipe builds | `bitbake vcontainer-tarball` |
| `TestMulticonfig` | Multiconfig setup | `BBMULTICONFIG` configured |
| `TestBundledContainersBoot` | **Boot image and verify containers** | Full image with Docker/Podman |
| `TestCustomServiceFileSupport` | CONTAINER_SERVICE_FILE varflag support | None (file check only) |
| `TestCustomServiceFileBoot` | Custom service files installed correctly | Full image with autostart containers |

### Boot Tests (TestBundledContainersBoot)

Boot tests actually start the built image in QEMU and verify bundled containers are visible and runnable. This is the ultimate verification that container-cross-install worked correctly.

#### Build Prerequisites

Before running boot tests, you need a built image with bundled containers:

```bash
cd /opt/bruce/poky
source oe-init-build-env

# Option 1: Package-based bundling (recommended)
# Ensure example-container-bundle is in IMAGE_INSTALL (already configured in local.conf):
#   IMAGE_INSTALL:append:pn-container-image-host = " example-container-bundle"

# Build the image (includes container bundling via vrunner/QEMU)
bitbake container-image-host

# Option 2: Legacy BUNDLED_CONTAINERS variable
# Add to local.conf:
#   BUNDLED_CONTAINERS = "container-base-latest-oci:podman"
# Then rebuild:
#   bitbake container-image-host -C rootfs
```

#### Additional Requirements

```bash
pip install pexpect
```

#### What Boot Tests Verify

1. **System boots** - Image boots successfully and reaches login prompt
2. **Docker images visible** - If Docker containers bundled, `docker images` shows them
3. **Podman images visible** - If Podman containers bundled, `podman images` shows them
4. **Docker run works** - Can actually run a bundled Docker container
5. **Podman run works** - Can actually run a bundled Podman container

#### Running Boot Tests

```bash
cd /opt/bruce/poky/meta-virtualization

# Run boot tests (requires built image with bundled containers)
pytest tests/test_container_cross_install.py::TestBundledContainersBoot -v

# Run with custom image
pytest tests/test_container_cross_install.py::TestBundledContainersBoot -v \
    --image container-image-host

# Disable KVM (slower, but works in VMs)
pytest tests/test_container_cross_install.py::TestBundledContainersBoot -v --no-kvm

# Longer boot timeout (default: 120s)
pytest tests/test_container_cross_install.py::TestBundledContainersBoot -v --boot-timeout 180
```

#### Boot Test Options

| Option | Default | Description |
|--------|---------|-------------|
| `--image NAME` | container-image-host | Image name to boot |
| `--image-fstype TYPE` | ext4 | Filesystem type (ext4, wic, etc.) |
| `--boot-timeout SECS` | 120 | Timeout for boot to complete |
| `--no-kvm` | (KVM enabled) | Disable KVM acceleration |

#### Container Detection

Boot tests automatically detect bundled containers using two methods:

1. **Direct detection (preferred)**: Reads container storage in the rootfs
   - Docker: `/var/lib/docker/image/overlay2/repositories.json`
   - Podman: `/var/lib/containers/storage/vfs-images/images.json`

2. **Legacy fallback**: Parses `BUNDLED_CONTAINERS` variable from `local.conf`

#### Test Skipping Behavior

Tests skip when no containers are detected:

- **No Docker containers** → Docker tests skip:
  `"No Docker containers in bundle packages or BUNDLED_CONTAINERS"`

- **No Podman containers** → Podman tests skip:
  `"No Podman containers in bundle packages or BUNDLED_CONTAINERS"`

- **No containers at all** → All container tests skip:
  `"No container bundles found (no containers in rootfs storage and no BUNDLED_CONTAINERS in local.conf)"`

- **Bundle package installed but no containers** → Skip with rebuild hint:
  `"Bundle packages installed but no containers detected in storage (image may need rebuild)"`

### Freshness Checking

Boot tests can detect when your rootfs is stale (older than source files) and warn or fail:

```bash
# Warn if rootfs older than OCI containers or bbclass (default: just warns)
pytest tests/test_container_cross_install.py::TestBundledContainersBoot -v

# Fail if rootfs is stale (CI mode)
pytest tests/test_container_cross_install.py::TestBundledContainersBoot -v --fail-stale

# Adjust max age before warning (default: 24 hours)
pytest tests/test_container_cross_install.py::TestBundledContainersBoot -v --max-age 48
```

#### Freshness Check Options

| Option | Default | Description |
|--------|---------|-------------|
| `--fail-stale` | false | Fail (not just warn) if rootfs is stale |
| `--max-age HOURS` | 24 | Max rootfs age in hours before warning |

#### What Gets Checked

The freshness check compares the rootfs mtime against:
1. **OCI container directories** - Any container in `BUNDLED_CONTAINERS`
2. **container-cross-install.bbclass** - The class that bundles containers

If any source is newer than the rootfs, you'll see:

```
WARNING: Rootfs may be stale!
  Rootfs: 2025-12-27 10:30:00
  Newer sources found:
    - container-app-base-latest-oci: 2025-12-28 14:22:33
  Consider rebuilding: bitbake container-image-host -C rootfs
```

#### Fresh Test Workflow

To ensure you're testing the latest functionality:

```bash
# 1. Rebuild containers (if changed)
bitbake container-base container-app-base

# 2. Rebuild image rootfs
bitbake container-image-host -C rootfs

# 3. Run boot tests with stale check
pytest tests/test_container_cross_install.py::TestBundledContainersBoot -v --fail-stale
```

### Running container-cross-install Tests

```bash
cd /opt/bruce/poky/meta-virtualization

# Run all container-cross-install tests (many are slow)
pytest tests/test_container_cross_install.py -v

# Run only fast tests (file checks, no building)
pytest tests/test_container_cross_install.py -v -m "not slow"

# Run with custom build directory
pytest tests/test_container_cross_install.py -v --build-dir /path/to/build

# Run specific test
pytest tests/test_container_cross_install.py::TestContainerCrossClass -v
```

### container-cross-install Test Options

| Option | Description |
|--------|-------------|
| `--poky-dir PATH` | Path to poky directory (default: /opt/bruce/poky) |
| `--build-dir PATH` | Path to build directory (default: $POKY_DIR/build) |
| `--machine MACHINE` | Target machine (default: qemux86-64) |
| `--image NAME` | Image to boot for boot tests (default: container-image-host) |
| `--image-fstype TYPE` | Filesystem type (default: ext4) |
| `--boot-timeout SECS` | Boot timeout in seconds (default: 120) |
| `--no-kvm` | Disable KVM acceleration for boot tests |
| `--fail-stale` | Fail if rootfs is older than source files |
| `--max-age HOURS` | Max rootfs age before warning (default: 24) |

---

## Xen Runtime Tests

Xen runtime tests boot an actual xen-image-minimal in QEMU and verify the Xen hypervisor is functional end-to-end. Tests detect available features inside Dom0 and skip gracefully when optional components are not installed.

### Build Prerequisites

| Test Tier | What to Add to `local.conf` | Build Command |
|-----------|---------------------------|---------------|
| **Dom0 boot** (core) | `DISTRO_FEATURES:append = " xen systemd"` | `bitbake xen-image-minimal` |
| **Guest bundling** | `IMAGE_INSTALL:append:pn-xen-image-minimal = " alpine-xen-guest-bundle"` | `bitbake xen-image-minimal` |
| **vxn/containerd** | `DISTRO_FEATURES:append = " virtualization vcontainer vxn"` and `IMAGE_INSTALL:append:pn-xen-image-minimal = " vxn"` and `BBMULTICONFIG = "vruntime-aarch64 vruntime-x86-64"` | `bitbake xen-image-minimal` |

The test locates the image at: `{build_dir}/tmp/deploy/images/{machine}/xen-image-minimal-{machine}.rootfs.wic`

### What the Tests Check

| Test Class | What It Tests | What's Needed |
|------------|---------------|---------------|
| `TestXenDom0Boot` | Hypervisor running, xl list, dmesg, memory cap | Core Xen image |
| `TestXenGuestBundleRuntime` | Bundled guests visible in xl list, xendomains active | Guest bundle packages |
| `TestXenVxnStandalone` | vxn binary present, `vxn run` works | vxn in image + network |
| `TestXenContainerd` | containerd active, ctr pull + vctr run | containerd + vctr + network |

### Running Xen Runtime Tests

```bash
cd /opt/bruce/poky/meta-virtualization

# All Xen runtime tests (requires built image + KVM)
pytest tests/test_xen_runtime.py -v --machine qemux86-64

# Skip network-dependent vxn/containerd tests
pytest tests/test_xen_runtime.py -v -m "boot and not network"

# Custom paths and longer timeout
pytest tests/test_xen_runtime.py -v \
    --poky-dir /opt/bruce/poky \
    --build-dir /opt/bruce/poky/build \
    --boot-timeout 180

# Disable KVM (slower, but works in VMs)
pytest tests/test_xen_runtime.py -v --no-kvm
```

### Xen Runtime Test Options

| Option | Default | Description |
|--------|---------|-------------|
| `--poky-dir PATH` | /opt/bruce/poky | Path to poky directory |
| `--build-dir PATH` | $POKY_DIR/build | Path to build directory |
| `--machine MACHINE` | qemux86-64 | Target machine (qemux86-64 or qemuarm64) |
| `--boot-timeout SECS` | 120 | Timeout for boot to complete |
| `--no-kvm` | (KVM enabled) | Disable KVM acceleration |

### Skip Behavior

Tests detect what's installed inside Dom0 and skip gracefully:

- **No .wic image** → All tests skip: `"xen-image-minimal .wic image not found"`
- **No pexpect** → All tests skip: `"pexpect not installed"`
- **Boot fails** → All tests skip: `"Failed to boot Xen image"`
- **No bundled guests** → Guest tests skip: `"No bundled guests detected"`
- **No xendomains** → xendomains test skips: `"xendomains service not installed"`
- **No vxn** → vxn tests skip: `"vxn not installed in image"`
- **No containerd** → containerd tests skip: `"containerd not installed"`
- **No vctr** → vctr test skips: `"vctr not installed in image"`

---

## Capturing Test Output

Test output is automatically captured to files for debugging:

| File | Contents |
|------|----------|
| `/tmp/pytest-vcontainer.log` | Python logging (DEBUG level) |
| `/tmp/pytest-results.xml` | JUnit XML results (for CI) |

To capture full stdout/stderr (including test failures and assertions):

```bash
# Capture everything to a log file
pytest tests/test_vpdmn.py --vdkr-dir /tmp/vcontainer 2>&1 | tee /tmp/pytest-output.log

# Then share the log file for debugging
cat /tmp/pytest-output.log
```

---

## Test Markers

| Marker | Description |
|--------|-------------|
| `slow` | Tests that take a long time (building recipes, images) |
| `memres` | Tests requiring vdkr memory resident mode |
| `network` | Tests requiring network access (docker pull, etc.) |
| `boot` | Tests that boot a QEMU image (requires built image) |

### Filtering by Marker

```bash
# Skip slow tests
pytest tests/ -m "not slow"

# Run only network tests
pytest tests/ -m network

# Combine markers
pytest tests/ -m "not slow and not network"
```

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `VDKR_STANDALONE_DIR` | Default path to vdkr standalone directory |
| `VDKR_ARCH` | Default architecture (x86_64 or aarch64) |
| `TEST_OCI_IMAGE` | Default OCI image for import tests |
| `POKY_DIR` | Path to poky directory |
| `BUILD_DIR` | Path to build directory |
| `MACHINE` | Target machine for Yocto builds |

---

## Test Structure

```
tests/
├── conftest.py                      # Fixtures and configuration
├── pytest.ini                       # Pytest settings
├── memres-test.sh                   # Helper to start/stop memres for tests
├── test_vdkr.py                     # vdkr (Docker) CLI tests
│   ├── TestMemresBasic              # memres start/stop/status
│   ├── TestImages                   # images, pull, rmi
│   ├── TestVimport                  # OCI import
│   ├── TestSaveLoad                 # save/load images
│   ├── TestVrun                     # container execution
│   ├── TestInspect                  # inspect command
│   ├── TestHistory                  # history command
│   ├── TestClean                    # clean command
│   ├── TestFallbackMode             # non-memres operation
│   ├── TestContainerLifecycle       # ps, stop, rm
│   └── TestVolumeMounts             # volume mount tests
├── test_vpdmn.py                    # vpdmn (Podman) CLI tests
│   ├── TestMemresBasic              # memres start/stop/status
│   ├── TestImages                   # images, pull, rmi
│   ├── TestVimport                  # OCI import
│   ├── TestSaveLoad                 # save/load images
│   ├── TestVrun                     # container execution
│   ├── TestRun                      # run with entrypoint override
│   ├── TestInspect                  # inspect command
│   ├── TestHistory                  # history command
│   ├── TestClean                    # clean command
│   ├── TestFallbackMode             # non-memres operation
│   ├── TestContainerLifecycle       # ps, stop, rm
│   └── TestVolumeMounts             # volume mount tests
├── test_container_cross_install.py  # Yocto integration tests
│   ├── TestContainerCrossClass      # bbclass syntax
│   ├── TestOCIImageBuild            # OCI generation
│   ├── TestBundledContainers        # end-to-end bundling
│   ├── TestVdkrRecipes              # vdkr builds
│   ├── TestMulticonfig              # multiconfig setup
│   ├── TestBundledContainersBoot    # boot and verify containers
│   ├── TestCustomServiceFileSupport # CONTAINER_SERVICE_FILE varflag support
│   └── TestCustomServiceFileBoot    # custom service file boot verification
├── test_multiarch_oci.py            # Multi-architecture OCI tests
│   ├── TestOCIImageIndexDetection   # multi-arch OCI detection
│   ├── TestPlatformSelection        # arch selection (aarch64/x86_64)
│   ├── TestGetOCIPlatforms          # platform listing
│   ├── TestExtractPlatformOCI       # single-platform extraction
│   ├── TestMultiArchOCIClass        # oci-multiarch.bbclass tests
│   ├── TestBackwardCompatibility    # single-arch OCI compat
│   ├── TestVrunnerMultiArch         # vrunner.sh multi-arch support
│   ├── TestVcontainerCommonMultiArch # vcontainer-common.sh support
│   └── TestContainerRegistryMultiArch # registry manifest list support
├── test_multilayer_oci.py           # Multi-layer OCI tests
│   ├── TestMultiLayerOCIClass       # OCI_LAYERS support
│   ├── TestMultiLayerOCIBuild       # layer build verification
│   └── TestLayerCaching             # layer cache tests
├── test_xen_runtime.py             # Xen runtime boot tests
│   ├── TestXenDom0Boot              # hypervisor running, xl list, dmesg
│   ├── TestXenGuestBundleRuntime    # bundled guests, xendomains
│   ├── TestXenVxnStandalone         # vxn run (network)
│   └── TestXenContainerd            # containerd + vctr (network)
└── README.md                        # This file
```

---

## Quick Reference

### Full Multi-Architecture Regression Test (recommended)

This builds everything needed for comprehensive testing of both x86_64 and aarch64:

```bash
# Build all components (blobs, SDK, images, containers for both architectures)
cd /opt/bruce/poky && source oe-init-build-env && \
bitbake mc:vruntime-aarch64:vdkr-initramfs-create && \
bitbake mc:vruntime-x86-64:vdkr-initramfs-create && \
bitbake mc:vruntime-aarch64:vpdmn-initramfs-create && \
bitbake mc:vruntime-x86-64:vpdmn-initramfs-create && \
MACHINE=qemux86-64 bitbake vcontainer-tarball && \
MACHINE=qemux86-64 bitbake container-image-host && \
MACHINE=qemuarm64 bitbake container-image-host && \
MACHINE=qemux86-64 bitbake container-app-base && \
MACHINE=qemuarm64 bitbake container-app-base
```

Then extract the SDK and run the full test suite:

```bash
# Extract SDK and run all tests
/opt/bruce/poky/build/tmp/deploy/sdk/vcontainer-standalone.sh -d /tmp/vcontainer -y && \
cd /opt/bruce/poky/meta-virtualization && \
pytest tests/ -v --vdkr-dir /tmp/vcontainer --poky-dir /opt/bruce/poky
```

To test a specific architecture:

```bash
# Test x86_64
pytest tests/ -v --vdkr-dir /tmp/vcontainer --poky-dir /opt/bruce/poky --arch x86_64

# Test aarch64
pytest tests/ -v --vdkr-dir /tmp/vcontainer --poky-dir /opt/bruce/poky --arch aarch64
```

---

### Full vdkr + vpdmn test run (single architecture)

```bash
# 1. Build the unified standalone SDK (includes both vdkr and vpdmn)
cd /opt/bruce/poky
source oe-init-build-env
MACHINE=qemux86-64 bitbake vcontainer-tarball

# 2. Extract the tarball (self-extracting installer)
/opt/bruce/poky/build/tmp/deploy/sdk/vcontainer-standalone.sh -d /tmp/vcontainer -y

# 3. Run fast tests for both tools (skips network and slow tests)
cd /opt/bruce/poky/meta-virtualization
pytest tests/test_vdkr.py tests/test_vpdmn.py -v --vdkr-dir /tmp/vcontainer -m "not network and not slow"

# 4. Run ALL tests for both tools (includes network tests like pull)
pytest tests/test_vdkr.py tests/test_vpdmn.py -v --vdkr-dir /tmp/vcontainer
```

### vdkr only test run

```bash
# Build SDK (includes both vdkr and vpdmn)
MACHINE=qemux86-64 bitbake vcontainer-tarball

# Extract
/opt/bruce/poky/build/tmp/deploy/sdk/vcontainer-standalone.sh -d /tmp/vcontainer -y

# Run vdkr tests only
pytest tests/test_vdkr.py -v --vdkr-dir /tmp/vcontainer
```

### With OCI image import test

```bash
# Run tests including OCI import (requires a built OCI image)
pytest tests/test_vdkr.py -v --vdkr-dir /tmp/vcontainer \
    --oci-image /opt/bruce/poky/build/tmp/deploy/images/qemux86-64/container-app-base-latest-oci
```

### Faster repeated runs (memres mode)

```bash
# Start memres once (keeps QEMU VM running)
./tests/memres-test.sh start --vdkr-dir /tmp/vcontainer

# Run tests multiple times (~1s per command vs ~30s cold boot)
pytest tests/test_vdkr.py -v --vdkr-dir /tmp/vcontainer --skip-destructive

# Stop memres when done
./tests/memres-test.sh stop --vdkr-dir /tmp/vcontainer
```

### Minimal container-cross-install test run

```bash
# Just check files exist (no building)
cd /opt/bruce/poky/meta-virtualization
pytest tests/test_container_cross_install.py::TestContainerCrossClass -v
```

### Boot test (verify bundled containers)

```bash
# 1. Ensure image is built with BUNDLED_CONTAINERS in local.conf:
#    BUNDLED_CONTAINERS = "container-base-latest-oci:docker container-app-base-latest-oci:docker"

# 2. Build the image
cd /opt/bruce/poky && source oe-init-build-env
bitbake container-image-host

# 3. Run boot tests
cd /opt/bruce/poky/meta-virtualization
pytest tests/test_container_cross_install.py::TestBundledContainersBoot -v

# 4. Run with freshness check (CI mode)
pytest tests/test_container_cross_install.py::TestBundledContainersBoot -v --fail-stale
```

---

## Adding New Tests

### vdkr tests

Use the `vdkr` or `memres_session` fixture:

```python
def test_my_command(memres_session):
    vdkr = memres_session
    result = vdkr.run("my-command", "arg1", "arg2")
    assert result.returncode == 0
    assert "expected" in result.stdout
```

### vpdmn tests

Use the `vpdmn` or `vpdmn_memres_session` fixture:

```python
def test_my_podman_command(vpdmn_memres_session):
    vpdmn = vpdmn_memres_session
    result = vpdmn.run("my-command", "arg1", "arg2")
    assert result.returncode == 0
    assert "expected" in result.stdout
```

### container-cross-install tests

Use `run_bitbake()` helper:

```python
def test_my_recipe(build_dir):
    result = run_bitbake(build_dir, "my-recipe")
    assert result.returncode == 0
```
