# vxn — Docker CLI for Xen DomU Containers

vxn runs OCI containers as Xen DomU guests. The VM IS the container — no
Docker/Podman daemon runs inside the guest. The guest boots a minimal Linux,
mounts the container's filesystem, and directly executes the entrypoint.

## Packages

| Package | Contents | Usage |
|---------|----------|-------|
| `vxn` | CLI, OCI runtime, blobs, containerd config | Base package (required) |
| `vxn-vdkr` | `vdkr` — Docker-like CLI frontend | `IMAGE_INSTALL:append = " vxn-vdkr"` |
| `vxn-vpdmn` | `vpdmn` — Podman-like CLI frontend | `IMAGE_INSTALL:append = " vxn-vpdmn"` |
| `vxn-docker-config` | `/etc/docker/daemon.json` (vxn as default runtime) | `IMAGE_INSTALL:append = " vxn-docker-config"` |
| `vxn-podman-config` | `/etc/containers/containers.conf.d/50-vxn-runtime.conf` | `IMAGE_INSTALL:append = " vxn-podman-config"` |

## Execution Paths

### 1. containerd (vctr/ctr) — recommended

No additional packages needed beyond `vxn`. containerd is configured
automatically via `/etc/containerd/config.toml`.

```bash
ctr image pull docker.io/library/alpine:latest
vctr run --rm docker.io/library/alpine:latest test1 /bin/echo hello
ctr run -t --rm --runtime io.containerd.vxn.v2 docker.io/library/alpine:latest tty1 /bin/sh
```

### 2. vdkr/vpdmn (Docker/Podman-like CLI, no daemon)

Install `vxn-vdkr` or `vxn-vpdmn`. These are standalone frontends that
auto-detect Xen (via `xl`) and manage containers without any daemon process.
They handle OCI image pull/unpack on the host via skopeo.

```bash
vdkr run --rm alpine echo hello        # Docker-like
vpdmn run --rm alpine echo hello       # Podman-like
```

Persistent DomU (memres) for faster subsequent runs:
```bash
vdkr vmemres start                     # Boot persistent DomU (~10s)
vdkr run --rm alpine echo hello        # Hot-plug container (~1s)
vdkr vmemres stop                      # Shutdown DomU
```

### 3. Native Docker with vxn runtime

Install `vxn-docker-config` to register vxn-oci-runtime as Docker's default
OCI runtime. Docker manages images (pull/tag/rmi) natively.

```bash
docker run --rm --network=none alpine echo hello
docker run --rm --network=host alpine echo hello
```

**IMPORTANT: Networking** — Docker's default bridge networking is incompatible
with VM-based runtimes. Docker tries to create veth pairs and move them into
a Linux network namespace, but vxn containers are Xen DomUs with their own
kernel network stack. You MUST use `--network=none` or `--network=host`.

This is the same limitation as kata-containers. The long-term fix is a TAP
bridge that connects Docker's network namespace to the DomU's vif (see TODO).

For selective use (keep runc as default, use vxn per-run):
```bash
docker run --rm --runtime=vxn --network=none alpine echo hello
```

### 4. Native Podman with vxn runtime

Install `vxn-podman-config` to register vxn-oci-runtime as Podman's default
OCI runtime. Same networking constraints as Docker.

```bash
podman run --rm --network=none alpine echo hello
```

## Build Instructions

```bash
# Prerequisites in local.conf:
DISTRO_FEATURES:append = " xen virtualization vcontainer"
BBMULTICONFIG = "vruntime-aarch64 vruntime-x86-64"

# Build (mcdepends auto-builds vruntime blobs)
bitbake vxn

# Dom0 image with containerd + Docker-like CLI
IMAGE_INSTALL:append = " vxn vxn-vdkr"

# Dom0 image with native Docker integration
IMAGE_INSTALL:append = " vxn vxn-docker-config docker"

bitbake xen-image-minimal
```

## Architecture

```
Docker/Podman/containerd → vxn-oci-runtime → xl create/unpause/destroy → Xen DomU
                                                                            ↓
                                                                      vxn-init.sh
                                                                        mount rootfs
                                                                        chroot + exec
```

The OCI runtime (`/usr/bin/vxn-oci-runtime`) implements the standard
create/start/state/kill/delete lifecycle by mapping to xl commands:

| OCI Command | xl Equivalent |
|-------------|---------------|
| create | xl create -p (paused) |
| start | xl unpause |
| state | xl list + monitor PID check |
| kill SIGTERM | xl shutdown (10s grace) + xl destroy |
| kill SIGKILL | xl destroy |
| delete | xl destroy + cleanup state |

## Networking Constraints (Native Docker/Podman)

Docker and Podman's default bridge networking creates Linux veth pairs and
moves one end into a container network namespace. This is fundamentally
incompatible with VM-based runtimes where the "container" is a VM with its
own kernel networking.

**Current workarounds:**
- `--network=none` — DomU uses its own xenbr0 networking
- `--network=host` — Tells Docker/Podman to skip namespace setup

**Future fix (TODO):**
TAP bridge integration — read Docker's network namespace config from
config.json, create a TAP device bridged to the DomU's vif. This is the
approach kata-containers uses to provide Docker-compatible networking with
VM isolation.

**Not affected:**
- `vctr`/`ctr` (containerd) — CNI is separate and opt-in
- `vdkr`/`vpdmn` — Handle networking independently via xenbr0

## Testing

Automated runtime tests boot xen-image-minimal and verify vxn end-to-end:

```bash
pip install pytest pexpect

# All Xen runtime tests (requires built image + KVM)
cd meta-virtualization
pytest tests/test_xen_runtime.py -v --machine qemux86-64

# vxn/containerd tests only
pytest tests/test_xen_runtime.py -v -k "Vxn or Containerd"

# Skip network-dependent tests
pytest tests/test_xen_runtime.py -v -m "boot and not network"
```

The tests boot the image with `qemuparams="-m 4096"` to provide enough
memory for Dom0 + bundled guests + vxn/vctr guests. Tests detect
available features inside Dom0 and skip gracefully when components are
not installed.

See `tests/README.md` for full test documentation and `recipes-extended/images/README-xen.md`
for build prerequisites at each test tier.

## Debugging

```bash
# OCI runtime log (all invocations)
cat /var/log/vxn-oci-runtime.log

# Per-container console capture (persists after container exit)
ls /var/log/vxn-oci-runtime/containers/

# Xen domain status
xl list

# Watch domain console
xl console <domname>

# Kill stuck domain
xl destroy <domname>
```
