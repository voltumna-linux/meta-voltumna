# Build Profiles — Configuration Fragments for meta-virtualization

## Overview

meta-virtualization provides configuration fragments in `conf/distro/include/`
that replace the manual DISTRO_FEATURES, CONTAINER_PROFILE, and related
settings typically scattered across `local.conf`. Each fragment is a small
`.conf` file that sets the minimum variables needed for a specific build
profile.

The fragments are organized in layers:

```
meta-virt-host.conf              <- base (always required first)
  container-host-docker.conf     <- container profiles (pick one)
  container-host-podman.conf
  container-host-containerd.conf
  container-host-k3s.conf
  container-host-k3s-node.conf
  container-host-incus.conf
  xen-host.conf                  <- Xen support (composable)
  kvm-host.conf                  <- KVM/libvirt support (composable)
meta-virt-dev.conf               <- QEMU dev settings (opt-in)
container-registry.conf          <- registry config (opt-in)

Distro configs:
  vruntime.conf                  <- minimal VM rootfs (BBMASK, busybox init)
  vcontainer.conf                <- OCI image builder (no BBMASK, full packages)
    both share: vruntime-base.inc  <- stripped DISTRO_FEATURES, opted-out features

Multiconfigs (set by meta-virt-host.conf):
  vruntime-aarch64               <- vdkr/vpdmn VM rootfs builds
  vruntime-x86-64
  container-aarch64              <- OCI container image builds
  container-x86-64
```

## Quick Start

Add to `local.conf`:

```bash
# Base (always first)
require conf/distro/include/meta-virt-host.conf

# Container profile — change BUILD_PROFILE to switch
BUILD_PROFILE ?= "podman"
require conf/distro/include/container-host-${BUILD_PROFILE}.conf

# Optional: Xen support (composable with any container profile)
require conf/distro/include/xen-host.conf

# Optional: QEMU development settings
require conf/distro/include/meta-virt-dev.conf

# Optional: Container registry
require conf/distro/include/container-registry.conf

MACHINE = "qemux86-64"
```

Then build:

```bash
bitbake container-image-host    # container host image
bitbake xen-image-minimal       # Xen image (if xen-host.conf included)
```

## Switching Profiles

Change one variable to switch the entire container stack:

```bash
BUILD_PROFILE ?= "docker"       # Docker + runc + CNI
BUILD_PROFILE ?= "podman"       # Podman + crun + netavark
BUILD_PROFILE ?= "containerd"   # Containerd + crun + CNI
BUILD_PROFILE ?= "k3s"          # K3s server + embedded containerd + CNI
BUILD_PROFILE ?= "k3s-node"     # K3s agent node
```

Or override from the command line:

```bash
BUILD_PROFILE=docker bitbake container-image-host
```

## Fragment Reference

### meta-virt-host.conf (Base — Required)

The foundation for all virtualization work. Must be included first.

**Sets:**
- `DISTRO_FEATURES:append = " virtualization systemd seccomp vmsep vcontainer"`
- `PREFERRED_PROVIDER_virtual/runc ?= "runc"`
- `BBMULTICONFIG ?= "vruntime-aarch64 vruntime-x86-64 container-aarch64 container-x86-64"`

The `vruntime-*` multiconfigs use the `vruntime` distro (BBMASK for minimal VM
rootfs). The `container-*` multiconfigs use the `vcontainer` distro (no BBMASK,
full OCI tooling available) for building multi-arch container images.

**Use standalone** for custom/mixed configurations where you want to set
CONTAINER_PROFILE and other variables manually.

### container-host-docker.conf

Docker engine stack.

**Sets:**
- `CONTAINER_PROFILE = "docker"`

**Results in:** docker-moby, runc, CNI networking.

### container-host-podman.conf

Podman engine stack.

**Sets:**
- `CONTAINER_PROFILE = "podman"`
- `DISTRO_FEATURES:append = " ipv6"` (required by podman packagegroup)

**Results in:** podman, crun, netavark + aardvark-dns networking.

### container-host-containerd.conf

Standalone containerd stack.

**Sets:**
- `CONTAINER_PROFILE = "containerd"`

**Results in:** containerd, crun, CNI networking.

### container-host-k3s.conf

K3s server (control plane + agent).

**Sets:**
- `CONTAINER_PROFILE = "k3s-host"`
- `DISTRO_FEATURES:append = " k3s"`

**Results in:** k3s-server, embedded containerd, CNI plugins.

### container-host-k3s-node.conf

K3s agent (worker node). Joins an existing k3s server cluster.

**Sets:**
- `CONTAINER_PROFILE = "k3s-node"`
- `DISTRO_FEATURES:append = " k3s"`

**Results in:** k3s-agent, embedded containerd, CNI plugins.

### xen-host.conf

Xen hypervisor support. Composable with any container profile.

**Sets:**
- `DISTRO_FEATURES:append = " xen vxn"`
- `IMAGE_INSTALL:append:pn-xen-image-minimal = " vxn containerd-opencontainers"`

**Use with:** `bitbake xen-image-minimal`

### kvm-host.conf

KVM/libvirt support. Composable with any container profile.

**Sets:**
- `DISTRO_FEATURES:append = " kvm"`

**Use with:** `bitbake kvm-image-minimal`

### meta-virt-dev.conf

QEMU development and testing settings. Only include when developing
and testing with runqemu.

**Sets:**
- `IMAGE_FSTYPES = "ext4"` (raw ext4 for persistent boots, no snapshots)
- `QB_XEN_CMDLINE_EXTRA ?= "dom0_mem=512M"`
- `QB_MEM ?= "-m 1024"`
- `EXTRA_IMAGE_FEATURES ?= "allow-empty-password empty-root-password allow-root-login post-install-logging"`

### container-registry.conf

Local development container registry. Defaults to insecure HTTP at
localhost:5000 with namespace "yocto".

**Sets:**
- `CONTAINER_REGISTRY_URL ?= "localhost:5000"`
- `CONTAINER_REGISTRY_NAMESPACE ?= "yocto"`
- `CONTAINER_REGISTRY_INSECURE ?= "1"`
- `IMAGE_FEATURES:append = " container-registry"`

**For secure (TLS) registries,** override after the require:

```bash
require conf/distro/include/container-registry.conf
CONTAINER_REGISTRY_URL = "registry.example.com:5000"
CONTAINER_REGISTRY_SECURE = "1"
CONTAINER_REGISTRY_USERNAME = "myuser"
```

## Multi-Architecture Container Images

The `container-aarch64` and `container-x86-64` multiconfigs build OCI
container images using the `vcontainer` distro. This distro shares the same
stripped `DISTRO_FEATURES` as `vruntime` (via `vruntime-base.inc`) but
without the BBMASK that blocks OCI tooling like umoci.

### Build Commands

```bash
# Single-arch container image
bitbake mc:container-x86-64:container-base

# Multi-arch OCI Image Index (aarch64 + x86_64)
bitbake container-base-multiarch

# Import into vdkr (auto-selects host platform)
vdkr vimport tmp/deploy/images/*/container-base-multiarch-multiarch-oci container-base:latest
```

### Custom Multi-Arch Recipes

Create a recipe that inherits `oci-multiarch`:

```
# myapp-container-multiarch.bb
SUMMARY = "Multi-arch myapp container"
LICENSE = "MIT"

inherit oci-multiarch

OCI_MULTIARCH_RECIPE = "myapp-container"
OCI_MULTIARCH_PLATFORMS = "aarch64 x86_64"
```

The `myapp-container.bb` recipe must inherit `image-oci` and produce OCI output.

### vcontainer vs vruntime

| | vruntime | vcontainer |
|--|----------|------------|
| **Purpose** | VM rootfs for vdkr/vpdmn | OCI container images |
| **BBMASK** | Aggressive (blocks OCI tools) | Lighter (keeps OCI tools) |
| **Init** | busybox | (per recipe) |
| **IMAGE_FSTYPES** | ext4 | (per recipe) |
| **Multiconfigs** | vruntime-aarch64, vruntime-x86-64 | container-aarch64, container-x86-64 |
| **Shared base** | vruntime-base.inc | vruntime-base.inc |

Both distros mask graphics, multimedia, desktop, virtualization platforms,
and orchestration tools. The difference is that vruntime additionally masks
OCI tooling (umoci, container-registry, image recipes, sloci) that
vcontainer needs for building container images.

## Design Notes

**Profiles are pure deltas.** They do not include `meta-virt-host.conf`
themselves. This avoids BitBake duplicate inclusion warnings when
combining multiple fragments (e.g., a container profile + xen-host.conf).
The user must always include `meta-virt-host.conf` first.

**`meta-virt-dev.conf` is separate** from the build profiles. It contains
settings that only matter for QEMU-based development (image format,
memory, debug features) and should not be included in production builds.

**Fragments use weak assignments (`?=`)** for most settings so they can
be overridden in `local.conf`. The exceptions are `CONTAINER_PROFILE`
and profile-specific `DISTRO_FEATURES:append` which use strong
assignments since they define the profile's identity.

## Example: Full Development local.conf

```bash
# After the standard Poky local.conf boilerplate...

CONF_VERSION = "2"

###############################################################################
# Virtualization Profile & Development Configuration
###############################################################################

# Base: virtualization systemd seccomp vmsep vcontainer + BBMULTICONFIG
require conf/distro/include/meta-virt-host.conf

# Container profile (switch BUILD_PROFILE to change)
BUILD_PROFILE ?= "podman"
require conf/distro/include/container-host-${BUILD_PROFILE}.conf

# Xen support (composable with any container profile)
require conf/distro/include/xen-host.conf

# QEMU development settings (IMAGE_FSTYPES, QB_MEM, debug features)
require conf/distro/include/meta-virt-dev.conf

# Container registry (insecure localhost:5000)
require conf/distro/include/container-registry.conf

# Additional local settings
DISTRO_FEATURES:append = " pam"
INIT_MANAGER = "systemd"
MACHINE = "qemux86-64"

# Provider overrides
include bruce-providers.inc

# Xen guest bundles
IMAGE_INSTALL:append:pn-xen-image-minimal = " example-xen-guest-bundle"
IMAGE_INSTALL:append:pn-xen-image-minimal = " alpine-xen-guest-bundle"
```

## Launch Commands

```bash
# Container host (podman/docker/containerd/k3s)
runqemu qemux86-64 container-image-host ext4 nographic kvm slirp

# Xen Dom0
runqemu qemux86-64 xen-image-minimal wic nographic kvm qemuparams="-m 4096"

# K3s with extra memory
runqemu qemux86-64 container-image-host ext4 nographic kvm slirp qemuparams="-m 4096"
```
