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

> **Note: netavark needs the native nftables kernel modules.** podman's default
> network backend (netavark) builds its firewall ruleset with the native
> nftables expression modules (`nft_ct`, `nft_nat`, `nft_chain_nat`, `nft_masq`,
> `nft_reject`, `nft_compat`). The stock `linux-yocto` kernel builds these as
> loadable modules, which a minimal image does not pull in automatically. Without
> them the workload never starts and netavark fails at container creation with:
>
> ```
> nft ... Error: Could not process rule: No such file or directory
> ```
>
> Make sure they are present in your image (they live outside this layer), e.g.:
>
> ```bitbake
> IMAGE_INSTALL:append = " \
>     kernel-module-nft-ct kernel-module-nft-nat kernel-module-nft-chain-nat \
>     kernel-module-nft-masq kernel-module-nft-reject kernel-module-nft-reject-inet \
>     kernel-module-nft-compat"
> ```
>
> On a kernel that builds these features in (`=y`) the modules and their
> `kernel-module-*` packages do not exist, and none of this is needed.

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
