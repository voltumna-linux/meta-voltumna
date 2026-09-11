# Booting and testing Ankaios in QEMU

`ankaios-image-minimal` is a small reference image used to exercise Eclipse
Ankaios end-to-end. It boots a single QEMU node running the Ankaios **server**
and **agent** with the **podman** runtime, and starts one hello-ankaios
workload from `/etc/ankaios/state.yaml`.

Reference target: **`MACHINE = "qemux86-64"`**.

## Prerequisites

Because the image pulls in `podman`, the following layers and distro settings
must be present in your build configuration (they live outside this layer):

* Layers: `meta-openembedded` (`meta-oe`, `meta-python`, `meta-networking`) and
  `meta-virtualization`, in addition to `openembedded-core`.
* systemd as the init manager, in your distro or `local.conf`:

  ```bitbake
  INIT_MANAGER = "systemd"
  ```

* Distro features:

  ```bitbake
  DISTRO_FEATURES:append = " virtualization seccomp"
  ```

`podman` requires the `seccomp` distro feature; the Ankaios recipes themselves
do not. systemd is required (enforced via `REQUIRED_DISTRO_FEATURES`) because it
mounts cgroups and configures DNS out of the box; with sysvinit you have to do
both manually before podman can run a workload.

## Build

```shell
MACHINE=qemux86-64 bitbake ankaios-image-minimal
```

## Boot

```shell
runqemu qemux86-64 ankaios-image-minimal nographic slirp qemuparams="-m 2048"
```

* `nographic` keeps everything on the serial console.
* `slirp` gives the guest outbound networking so podman can pull
  `docker.io/alpine:latest` on first start.

Log in as `root` on the serial console with no password. The image sets
`allow-empty-password empty-root-password allow-root-login`, so this is a
debug/test image and not suitable for production use.

## Verify the workload

The server auto-starts from `/etc/ankaios/state.yaml`, the agent registers as
`agent_A`, and podman pulls and runs the `hello-ankaios` workload. Query the state
with the `ank` CLI:

```shell
ank get workloads
```

Expected output (the pull may take a few seconds on first boot, during which
the state passes through `Pending(...)`):

```
 WORKLOAD NAME   AGENT     RUNTIME   EXECUTION STATE   ADDITIONAL INFO
 hello-ankaios   agent_A   podman    Running(Ok)
```

You can cross-check at the runtime level:

```shell
podman ps
```

which should list the running `hello-ankaios` container.

## Tear down

Stop the workload by deleting it through Ankaios (the agent tells podman to
remove the container):

```shell
ank delete workload hello-ankaios
```

`ank get workloads` should then show no workloads, and `podman ps` no
containers. To shut the whole node down, power off the guest:

```shell
poweroff
```

or terminate QEMU from the host with `Ctrl-a x` (in `nographic` mode).
