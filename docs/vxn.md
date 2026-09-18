# vxn: containers as Xen DomU guests

vxn is a container runtime where the VM **is** the container. Each container
runs as a Xen PV DomU with its own kernel and memory, not as a namespace
sharing the host's. This gives VM-strength isolation (separate kernel, own
memory, no shared filesystem, no shared syscall surface) with an
OCI-compatible interface: `docker`, `podman`, or `ctr` can drive it without
knowing the container is a Xen guest.

For the SDK build path (produce a relocatable tarball with `vxn` + a
Xen dom0 image), see `vxn-sdk.md`. This document covers how vxn works,
its interfaces, and how to use it directly.

## Model

```
Xen Dom0 (host)                         Xen DomU (guest = the container)
┌─────────────────────────────┐        ┌─────────────────────────────┐
│ vxn run --rm hello-world    │        │ vcontainer-preinit.sh       │
│         ↓                   │        │   - Mount rootfs.img        │
│ vcontainer-common.sh        │        │   - switch_root to overlay  │
│   - Pull/unpack OCI image   │        │         ↓                   │
│   - Pass rootfs via 9p/blk  │        │ vxn-init.sh                 │
│   - Pass cmd via cmdline    │        │   - Detect Xen (hvc0/xvd*)  │
│         ↓                   │        │   - Mount container rootfs  │
│ vrunner.sh                  │        │   - chroot + exec entrypoint│
│         ↓                   │  xl    │   - Output via PV console   │
│ vrunner-backend-xen.sh      │───────→│   (OR daemon command loop)  │
│   - xl create [-c]          │ create │                             │
│   - xl shutdown/destroy     │←───────│                             │
│   - iptables port forwards  │ hvc0   │                             │
└─────────────────────────────┘        └─────────────────────────────┘

Drive layout (Xen PVH):
  /dev/xvda = rootfs.img         (read-only squashfs, minimal Linux)
  /dev/xvdb = container rootfs   (OCI image, passed from host [or via 9p])

Console:
  hvc0 = primary PV console (output, interactive)
  hvc1 = daemon command channel (daemon mode)
```

The guest rootfs (`rootfs.img`) is the `vruntime` multiconfig build. It
carries busybox, networking tools, and optionally docker/containerd/podman.
They are available if needed but not started by default. The init script
directly executes the container's entrypoint.

## The three ways to reach a DomU

vxn exposes three interfaces. All three converge on `xl create` producing a
Xen DomU that runs `vxn-init.sh` as PID 1.

### 1. The `vxn` CLI (custom entry path)

`vxn` is the Docker-like frontend that speaks the vcontainer family
protocol. It is a member of `vdkr`/`vpdmn`/`vxn`:

```
      vdkr                    vpdmn                    vxn
   "docker" CLI            "podman" CLI          "docker" CLI (Xen)
   default: QEMU           default: QEMU         default: qemu-xen
   (xen if `xl`)           (xen if `xl`)         (xen if in dom0)
       │                       │                      │
       │                       │                      │
       └───────────────────────┼──────────────────────┘
                               ▼
               ┌──────────────────────────────────┐
               │       vcontainer-common.sh        │  arg parse, config,
               │  CLI dispatch · daemon (memres) · │  daemon (memres),
               │  vexpose · image cache · ssh      │  vexpose, ssh
               └──────────────────────────────────┘
                               │  invokes the run engine
                               ▼
               ┌──────────────────────────────────┐
               │            vrunner.sh             │  build input ext4 disk,
               │  input-disk build · VM launch ·   │  launch VM, run command,
               │  IPC · daemon loop · idle watchdog│  daemon loop
               └──────────────────────────────────┘
                               │  sources ONE:  vrunner-backend-${HYPERVISOR}.sh
         ┌─────────────────────┼───────────────────────────┐
         ▼                     ▼                            ▼
  backend-qemu.sh       backend-xen.sh            backend-qemu-xen.sh
  plain QEMU guest      real Xen dom0 (xl)        QEMU-hosted Xen dom0
  (vdkr/vpdmn           (vxn in-dom0;             (vxn host-side/WSL: boots
   cross-arch)           vdkr/vpdmn if `xl`)       the dom0 .wic under QEMU,
                                                   proxies commands into dom0)
```

`vdkr` ↔ `vpdmn` differ only by `docker` vs `podman` semantics; `vxn`
differs by targeting Xen instead of QEMU. Backend selection is by
`VCONTAINER_HYPERVISOR` and `vrunner.sh` sources
`vrunner-backend-${HYPERVISOR}.sh`.

### 2. `vxn-oci-runtime` (standard OCI runtime)

`vxn-oci-runtime` implements the OCI runtime spec (create / start / state /
kill / delete). It lives on dom0. containerd / docker / podman treat it
like a `runc` replacement:

```
  CUSTOM CLI iface                   STANDARD-ENGINE iface (docker/podman/ctr)
  ───────────────                    ────────────────────────────────────────
  $ vxn run alpine                   $ docker run … │ podman run … │ ctr run …
        │                                    │
  vcontainer-common.sh               dockerd / podman / containerd
        │                              (vxn-oci-runtime = default runtime;
  vrunner.sh                           containerd via containerd-shim-vxn-v2)
        │                                    │
  backend-qemu-xen / -xen            ┌──────────────────────────────┐
        │                            │        vxn-oci-runtime        │  standalone
        │                            │  create/start/state/kill/     │  OCI runtime
        │                            │  delete  (+VXN_INJECT_DIR,    │
        │                            │  rw rootfs)                   │
        │                            └──────────────────────────────┘
        └──────────────┬───────────────────────┘
                       ▼
                  xl create / xl unpause
                       ▼
        ┌───────────────────────────────────────┐
        │   Xen PV DomU  =  "the container"      │   PID 1 = vxn-init.sh
        │   rootfs = image ext4 on xvdb (rw)     │   xenbr0 vif + NAT
        │   xvda = vruntime rootfs blob (ro)     │
        └───────────────────────────────────────┘
```

Both interfaces produce a Xen DomU. They differ in the entry path: the `vxn`
CLI goes through `vcontainer-common.sh` + `vrunner` + a backend; the stock
engines go through `vxn-oci-runtime` directly.

### 3. Native docker / podman / ctr via `vexpose`

A third path unifies the picture: `vexpose` exposes the docker / podman /
containerd daemon **running on dom0** to the outside, so the *native*
client drives it. The variable that changes between vdkr/vpdmn and vxn is
which OCI runtime the daemon calls:

```
        native docker / podman / ctr   (host)
                    │   DOCKER_HOST / CONTAINER_HOST  (client's own transport)
                    ▼
        a real docker / podman / containerd daemon … running in a VM
                    │   delegates each container to its OCI runtime
          ┌─────────┴──────────────────────────┐
          ▼                                     ▼
     runc / crun                          vxn-oci-runtime
     vdkr/vpdmn: daemon lives IN the      vxn: daemon lives on the Xen dom0
     QEMU VM; transport = tcp://          (dom0 may itself be a QEMU VM);
     localhost:2375  (QEMU hostfwd)       transport = ssh://vxn-dom0
          ▼                                     ▼
     namespace container                  a whole Xen DomU
     (shares the VM's kernel)             (its own kernel — one VM per container)
```

| | transport → daemon in… | OCI runtime | a container becomes… |
|-|------------------------|-------------|----------------------|
| **vdkr/vpdmn** | the QEMU VM (`tcp://…:2375`, QEMU hostfwd) | runc / crun | a **namespace** inside that one VM |
| **vxn** | the dom0 QEMU VM (`ssh://vxn-dom0`) | **vxn-oci-runtime** | a **new Xen DomU** per container |

Inside a real Xen dom0 (bare metal or your own hypervisor build, no QEMU
around dom0) the transport collapses: native `docker`/`ctr` talk to the
local daemon and `vxn-oci-runtime` / `xl` are right there. The
`ssh://vxn-dom0` transport exists only to bridge the host↔dom0 gap that
QEMU-hosted dom0 creates.

## Guest-side init: `vxn-init.sh`

`vxn-init.sh` runs as PID 1 in the DomU. It sources `vcontainer-init-common.sh`
for the shared plumbing that both vxn and vdkr/vpdmn need, then diverges at
the execution step:

```
vcontainer-init-common.sh (shared):
  ├── setup_base_environment()     # PATH, HOME, etc.
  ├── mount_base_filesystems()     # /dev, /proc, /sys, detect hypervisor
  ├── mount_tmpfs_dirs()           # /tmp, /run, /etc overlay
  ├── setup_cgroups()              # cgroup2 or v1
  ├── check_quiet_boot()           # suppress messages in interactive mode
  ├── parse_cmdline()              # decode runtime command from kernel params
  ├── detect_disks()               # find /dev/xvd* devices
  ├── mount_input_disk()           # mount container rootfs from xvdb
  └── configure_networking()       # DHCP on Xen bridge

vxn-init.sh (vxn-specific):
  ├── Mount container rootfs from input (9p or /dev/xvdb)
  ├── Parse OCI config for entrypoint/cmd/env/workdir
  ├── Set up container environment
  ├── chroot/pivot_root into container rootfs
  └── exec entrypoint
      ├── Non-interactive: capture output, send via console protocol
      ├── Interactive:     connect stdin/stdout to hvc0
      └── Daemon mode:     command loop on hvc1
```

`find_container_rootfs` has a **direct-mount branch**: if the input disk
contains `bin/` or `usr/` at the top level, it is used as the container
rootfs directly (no OCI extraction). This is how the "run a host binary
in a DomU" path works: see `docs/vxn-host-binary.md`.

## Nested enforcement

The VM boundary is the big-ticket isolation (separate kernel, own rootfs,
memory cap, no host filesystem). **Nested enforcement** adds fine-grained
policy inside the DomU as defense-in-depth: even a fully compromised agent
in the guest is bounded by the policy's resource / filesystem / syscall
rules, not just the VM ceiling.

Policy is applied by `vxn-init` in the guest before the entrypoint runs,
using shell + small helpers rather than a compiled in-guest enforcer.
The policy is serialized on the host, base64-encoded, passed via the
kernel command line, and applied by `vxn-init` before executing the
entrypoint.

Phases:

- **Phase 1 — cgroup v2 resource limits.** Done. Memory / CPU / PIDs
  ceilings are applied to the entrypoint's cgroup before `exec`.
- **Phase 2 — filesystem bind-mount view.** Done. Read-only and read-write
  bind mounts, tmpfs overrides, and hidden paths are constructed from the
  policy before `chroot`.
- **Phase 3 — seccomp.** Parked. Requires a compiled guest helper (the
  bpf(2) program) rather than pure shell.
- **Phase 4 — network policy.** Parked. Overlaps with the DomU's vif +
  iptables layer on dom0.

Phases 3 and 4 are deferred until asked; the current shipped state is
Phases 1+2.

## Interactive console geometry

Interactive `vxn -it` runs a real PTY on dom0 via `ssh -tt`; the guest
console (`hvc0`) receives that PTY. Two pieces of geometry work are done
so full-screen agents (`claude`, `less`, `top`) render at the right size:

- **`TERM=xterm-256color`** — set explicitly by `vxn-init` so guest
  programs get 256-color support.
- **Initial window size** — the host's `stty size` at launch is forwarded
  and applied to `hvc0` before the entrypoint runs. Prevents the "content
  wraps at 80 columns" symptom in a 200-column terminal.

Live resize (SIGWINCH forwarded mid-session to update `hvc0` geometry
after a window resize) is designed but not shipped. The initial-size fix
covers the common case where the terminal is not resized after launch.

## File layout on dom0

```
/usr/bin/vxn                       # CLI entry point
/usr/bin/vxn-oci-runtime           # OCI runtime binary (shell)
/usr/bin/vxn-sendtty               # SCM_RIGHTS helper (C binary)
/usr/bin/containerd-shim-vxn-v2    # Shim wrapper
/usr/bin/vctr                      # ctr + --runtime io.containerd.vxn.v2
/usr/bin/vdkr                      # Docker-like CLI (vxn-vdkr sub-package)
/usr/bin/vpdmn                     # Podman-like CLI (vxn-vpdmn sub-package)
/usr/libexec/vxn/shim/runc         # Symlink → vxn-oci-runtime (PATH trick)
/etc/containerd/config.toml        # containerd config
/etc/docker/daemon.json            # Docker config (vxn-docker-config)
/etc/containers/containers.conf.d/50-vxn-runtime.conf  # Podman config
/usr/lib/vxn/
├── vrunner.sh
├── vrunner-backend-xen.sh
├── vrunner-backend-qemu.sh
└── vcontainer-common.sh
/usr/share/vxn/
└── {aarch64,x86_64}/
    ├── Image                      # Xen PVH-capable kernel
    ├── initramfs.cpio.gz          # Preinit + vxn-init
    └── rootfs.img                 # vruntime squashfs
```

## Build

There are two build paths for a vxn-enabled dom0, corresponding to the
two use cases: adding vxn to your own Xen dom0 build, and producing the
relocatable SDK dom0 that ships in the vxn tarball.

### Adding vxn to your own dom0 (`local.conf` fragments)

The layer ships fragments under `conf/distro/include/` so you do not
hand-list features. `xen-host.conf` gives a plain Xen dom0; `vxn-host.conf`
layers vxn tooling on top of that:

```
# local.conf
require conf/distro/include/meta-virt-host.conf
require conf/distro/include/vxn-host.conf

MACHINE = "qemux86-64"
bitbake xen-image-minimal
```

`vxn-host.conf` sets `DISTRO_FEATURES += "xen vxn"` and pulls the vxn
package + containerd + `vxn-docker-config` into `xen-image-minimal`. A
`require xen-host.conf` alone (without `vxn-host.conf`) gives a plain
Xen dom0 with no vxn — being a Xen host does not imply vxn.

### Building the SDK dom0 (`vxn-*` multiconfig)

The vxn SDK dom0 is built via a dedicated multiconfig, not via
`local.conf` fragments. Two flavors ship, one per container engine on
dom0:

```
# BBMULTICONFIG (or explicit -c)
bitbake mc:vxn-x86-64:xen-image-minimal            # docker flavor
bitbake mc:vxn-podman-x86-64:xen-image-minimal     # podman flavor
```

The multiconfig sets `DISTRO_FEATURES` and `IMAGE_INSTALL` itself, so
it does NOT need `xen-host.conf` / `vxn-host.conf` in `local.conf` —
the two paths are independent by design. See `vxn-sdk.md` for
`bitbake vcontainer-tarball` (the full SDK build).

### dom0 engine flavor at launch

`docker-moby` and `podman` both own `/usr/bin/docker`, so a single dom0
image can carry only one engine. The SDK ships a separate blob per
flavor (`VXN_DOM0_FLAVORS = "docker podman"`, see `vxn-sdk.md`) as
`vxn-blobs/<arch>/xen-dom0-<flavor>.wic`, and the launcher selects one:

- `VXN_DOM0_FLAVOR=podman` (env) — honored by the `vxn` CLI and by
  `boot-xen.sh`.
- `boot-xen.sh --flavor podman` — the equivalent flag on the standalone
  launcher.
- `VXN_IMAGE=/path/to/xen-dom0-<flavor>.wic` — explicit blob, bypasses
  resolution.

A Xen host has a single dom0, so one flavor is active per launch;
switching flavor = relaunch against the other blob (`vxn memres stop`
first if a persistent dom0 is running). Default is `docker`; asking for
a flavor the SDK didn't ship fails loudly with the available list rather
than silently falling back.

### Blob dependencies

The vruntime blobs (kernel + initramfs + rootfs) that end up on dom0
under `/usr/share/vxn/<arch>/` come from the `vruntime-<arch>`
multiconfigs and are assembled by `vxn-initramfs-create` before the vxn
target package packages them:

```
mc:vruntime-<arch>:vdkr-tiny-initramfs-image  ← preinit + vxn-init
mc:vruntime-<arch>:vdkr-rootfs-image           ← squashfs with tools
mc:vruntime-<arch>:virtual/kernel              ← Xen PVH-capable kernel
        ↓ (mcdepends in vxn-initramfs-create.inc)
vxn-initramfs-create  ← assembles blobs to deploy/vxn/
        ↓
vxn  ← packages blobs + scripts into Dom0 rootfs
        ↓
xen-image-minimal
```

There is deliberately no task-level dependency from `vxn` to
`vxn-initramfs-create`: the deploy-only recipe would break the vxn
`do_rootfs` sstate manifest. When building manually, run
`bitbake vxn-initramfs-create` first if the blobs are stale.
```

Runtime dependencies on dom0: `xen-tools-xl`, `bash`, `jq`, `socat`,
`coreutils`, `util-linux`.

## Sub-packages

| Package | Provides | RDEPENDS |
|---------|----------|----------|
| `vxn` | CLI + oci-runtime + shim + libs + blobs | bash, jq, socat |
| `vxn-vdkr` | `/usr/bin/vdkr` | vxn |
| `vxn-vpdmn` | `/usr/bin/vpdmn` | vxn |
| `vxn-docker-config` | `/etc/docker/daemon.json` | vxn, docker |
| `vxn-podman-config` | `/etc/containers/containers.conf.d/50-vxn-runtime.conf` | vxn, podman |

`vxn-docker-config` sets `"iptables": false` in `daemon.json` — without
that, Docker's `FORWARD DROP` policy blocks xenbr0 DHCP for DomU vifs.

## Networking

Xen uses bridge networking:

- Dom0 side: DomU vif attached to `xenbr0` bridge, dom0 provides NAT.
- Guest side: DHCP via `udhcpc` (static fallback: 10.0.0.15/24).
- DNS: 8.8.8.8, 1.1.1.1 (dom0 does not proxy DNS the way QEMU slirp does).
- Port forwards: iptables DNAT rules on dom0, cleaned up on `xl destroy`.

### Docker / Podman bridge networking constraint

Docker's and Podman's default bridge mode creates a veth pair with one end
in a Linux network namespace. That is incompatible with a VM-per-container
runtime: the DomU has its own network stack, not a namespace. When
driving vxn via native `docker` or `podman`, pass `--network=none`:

```bash
docker run --rm --network=none alpine echo hello
podman run --rm --network=none alpine echo hello
```

`vxn`, `vdkr`, `vpdmn`, and `ctr` do not have this constraint — they
speak to `vxn-oci-runtime` directly and vxn sets up the vif on dom0.

## Using vxn

### The `vxn` CLI

```bash
# One-shot, foreground (--rm auto-cleans on exit)
vxn run --rm alpine echo hello

# Interactive shell
vxn run -it --rm alpine /bin/sh

# Persistent DomU (faster subsequent runs; boot happens once)
vxn memres start
vxn run alpine echo hello       # ~1s (no boot)
vxn memres stop

# OCI image cache (host-side, content-addressed)
vxn pull alpine                 # skopeo → ~/.vxn/images/
vxn images                      # list cached
vxn image inspect alpine        # show OCI config
vxn tag alpine myalpine:v1      # add ref
vxn rmi alpine                  # remove from cache

# Container lifecycle (per-container DomU)
vxn run -d --name web nginx     # detached
vxn ps                          # list running / exited
vxn exec web ls /               # send a command to a running DomU
vxn logs web                    # retrieve stdout/stderr
vxn stop web                    # xl shutdown / xl destroy
vxn rm web                      # tear down state dir
```

### Via containerd (`ctr` / `vctr`)

```bash
ctr image pull docker.io/library/alpine:latest

# vctr = ctr + --runtime io.containerd.vxn.v2 baked in
vctr run --rm docker.io/library/alpine:latest test1 /bin/echo hello

# Interactive PTY (job control, Ctrl-C)
ctr run -t --rm --runtime io.containerd.vxn.v2 \
    docker.io/library/alpine:latest test-tty /bin/sh

# Detached
vctr run -d docker.io/library/alpine:latest test-daemon /bin/sleep 3600
ctr task list
ctr task kill test-daemon
ctr task delete test-daemon
ctr container delete test-daemon
```

### Native docker / podman

Install the `vxn-docker-config` or `vxn-podman-config` sub-package. It
registers `vxn-oci-runtime` as the default runtime.

```bash
docker run --rm --network=none alpine echo hello
podman run --rm --network=none alpine echo hello
```

### The vdkr / vpdmn frontends

Installed as sub-packages of `vxn`. They auto-detect Xen (`xl` in `PATH`)
and route to `vxn-oci-runtime`; on a non-Xen host they fall back to their
own QEMU backend.

```bash
vdkr run --rm alpine echo hello         # Docker-like, auto-detects Xen
vpdmn run --rm alpine echo hello        # Podman-like

vdkr memres start                       # Persistent DomU
vdkr run --rm alpine echo hello         # ~1s (no boot)
vdkr memres stop
```

## Debugging

```bash
# Verbose CLI output
vxn -v run --rm alpine echo hello

# What Xen sees
xl list
xl console <domname>

# Daemon state (persistent DomU mode)
ls -la ~/.vxn/aarch64/
cat  ~/.vxn/aarch64/daemon.domname

# xl output log (captured when running under vrunner)
cat ~/.vxn/aarch64/qemu.log

# Kill a stuck domain
xl destroy $(cat ~/.vxn/aarch64/daemon.domname)
rm -f ~/.vxn/aarch64/daemon.*

# Poke the daemon command socket
echo "===PING===" | socat - UNIX-CONNECT:$HOME/.vxn/aarch64/daemon.sock
```

## Comparison with sibling frontends

|                     | vdkr                        | vpdmn                       | vxn                          |
|---------------------|-----------------------------|-----------------------------|------------------------------|
| CLI                 | `docker`-like               | `podman`-like               | `docker`-like                |
| Default backend     | QEMU                        | QEMU                        | qemu-xen (or xen if in dom0) |
| Container is        | a namespace in one big QEMU VM | a namespace in one big QEMU VM | a whole Xen DomU per container |
| Cross-arch runtime  | yes (aarch64 host runs x86_64 containers, etc.) | yes | limited to arch of dom0 |
| Concurrent containers | many, share the VM's kernel | many, share the VM's kernel | many, each with its own kernel |
| Interactive PTY    | yes                          | yes                          | yes                          |
| OCI runtime surface | (proxies to the VM's daemon) | (proxies to the VM's daemon) | `vxn-oci-runtime` on dom0    |

If you want VM isolation *per container*. A compromise inside one
container cannot see or reach into another, that's what vxn gives you.
If you want the lightest possible container with cross-arch execution,
that's vdkr/vpdmn.
