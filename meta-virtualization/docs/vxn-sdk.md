# Building a vxn SDK from Yocto

`vxn` is "Docker for Xen": it runs each container as a Xen PV DomU (a small VM
with its own kernel) instead of as a host namespace. The **vxn SDK** is a
relocatable, self-contained tarball produced by this layer that bundles:

- `vxn` — the host CLI (Docker-like: `run`, `ps`, `images`, `pull`, `provision`, …)
- a **Xen dom0 image** (`xen-image-minimal`) that boots under QEMU (KVM-accelerated)
  and hosts the container DomUs
- `vdkr` / `vpdmn` — the Docker / Podman cross-arch CLIs (always included)

Once installed, a user runs `vxn run --rm alpine echo hi` on any Linux host (or
WSL2) with `/dev/kvm` — no Xen hardware, no manual dom0 setup. This document
covers building that SDK yourself. For *using* it, the extracted SDK ships a
`README.txt` with the full runtime reference.

## Prerequisites

- A working Poky / OpenEmbedded build environment (`oe-init-build-env` sourced).
- `meta-virtualization` and its layer dependencies (`meta-openembedded`'s
  `meta-oe`, `meta-python`, `meta-networking`, `meta-filesystems`) in
  `bblayers.conf`.
- A host with `/dev/kvm` for reasonable speed (TCG works but is slow). KVM is
  used only to accelerate the QEMU that runs the dom0 — the target itself is a
  Xen guest.
- Disk: the dom0 image carries real container images at runtime, so it is sized
  with headroom (~10 GB by default, see `VXN_DOM0_EXTRA_SPACE` below).

vxn is **x86_64 only** today. aarch64 vdkr/vpdmn work; aarch64 Xen dom0 boots
via a different mechanism and is a follow-up.

## Configure the build

Add to `conf/local.conf`:

```
# Container + Xen + vxn distro features
DISTRO_FEATURES:append = " virtualization systemd seccomp vmsep vcontainer xen vxn"
INIT_MANAGER = "systemd"

# Multiconfigs: vruntime-* builds the vdkr/vpdmn rootfs; vxn-* builds the
# Xen dom0 image. vxn is x86_64-only for now.
BBMULTICONFIG = "vruntime-x86-64 vxn-x86-64"

# Opt in to bundling the vxn dom0 blob into the tarball (off by default —
# vxn is more niche than vdkr/vpdmn).
VCONTAINER_INCLUDE_VXN = "1"
```

Equivalent configuration is available as the ready-made fragments in
`conf/distro/include/` (`meta-virt-host.conf` + `xen-host.conf`) — see
[build-profiles.md](build-profiles.md). If you use those, still set
`VCONTAINER_INCLUDE_VXN = "1"` and ensure `vxn-x86-64` is in `BBMULTICONFIG`.

## Build

```
bitbake vcontainer-tarball
```

This builds the vdkr/vpdmn rootfs (vruntime MC), the Xen dom0 image
(`mc:vxn-x86-64:xen-image-minimal`), and packages them into an SDK via Yocto's
`populate_sdk`.

Output in `tmp/deploy/sdk/`:

```
vcontainer-standalone-x86_64.tar.xz     # the SDK archive
vcontainer-standalone-x86_64.sh         # self-extracting installer
```

The `.sh` is self-contained and relocatable — it is what you hand to another
user.

## Install and verify

On the target host (the machine that will run containers):

```
./vcontainer-standalone-x86_64.sh        # extracts to a directory you choose
cd <install-dir>
source init-env.sh                       # puts vxn / vdkr / vpdmn on PATH
vxn-x86_64 run --rm alpine echo hi        # boots dom0 once, runs the container
```

First run boots the dom0 under QEMU (~30 s) and leaves it resident (memres);
later commands reuse it and return in ~1 s.

## Options

Build-time (in `local.conf`):

| Variable | Default | Effect |
|----------|---------|--------|
| `VCONTAINER_INCLUDE_VXN` | `0` | set to `1` to bundle the vxn dom0 blob |
| `VCONTAINER_ARCHITECTURES` | `x86_64 aarch64` | which arches to build vdkr/vpdmn for |
| `VXN_DOM0_EXTRA_SPACE` | `10000000` | dom0 rootfs headroom (KB) for container images |

Run-time (env vars, host side):

| Variable | Effect |
|----------|--------|
| `VXN_VCPUS` / `VXN_MEM` | vCPUs / memory for the **dom0** QEMU VM |
| `VXN_MEMORY` / `VXN_VCPUS` | vCPUs / memory for each **container DomU** |
| `VXN_SSH_PORT` / `VXN_API_PORT` | dom0 ssh / exposed-engine ports |

## Corporate TLS-intercepting proxy

If image pulls fail with `x509: certificate signed by unknown authority`, drop
your corporate root CA (PEM) into the SDK's `certs/` directory and re-run any
command — it is installed into the dom0 / container trust store on boot. See the
`certs/README` in the extracted SDK.

## Limitations

- x86_64 only (aarch64 dom0 is a follow-up).
- The bundled dom0 pulls guest images at runtime over its NAT network, so the
  first pull needs egress (or a local registry / `vxn load`).

## Next

- The extracted SDK's `README.txt` documents the three runtime modes
  (transparent CLI, docker/podman-over-vexpose, interactive dom0 shell).
- Container bundling / cross-install and the vdkr/vpdmn tooling:
  [container-bundling.md](container-bundling.md).
