# Incus: System Container and VM Manager

[Incus](https://linuxcontainers.org/incus/) is the community fork of LXD,
providing a unified experience for running and managing system containers
and virtual machines. Built on LXC 6.0 with cowsql for distributed cluster state.

## Quick Start

### Build

Select the incus profile in your `local.conf`:

```
BUILD_PROFILE ?= "incus"
```

Or append incus to an existing image:

```
IMAGE_INSTALL:append:pn-container-image-host = " incus"
```

Then build:

```shell
bitbake container-image-host
```

### Boot

```shell
runqemu qemux86-64 nographic slirp qemuparams="-m 4096"
```

### Initialize

```shell
incus admin init --minimal
```

### Launch a container

```shell
incus launch images:alpine/edge test1
incus list
incus exec test1 -- /bin/sh
```

### Stop and delete

```shell
incus stop test1
incus delete test1
```

## Dependencies

Incus requires two C libraries that are provided as separate recipes:

- **raft** (`recipes-containers/raft/`) - Raft consensus protocol implementation
- **cowsql** (`recipes-containers/cowsql/`) - Distributed SQLite built on raft

Runtime dependencies (pulled in automatically via RDEPENDS):

- lxc, lxcfs, dnsmasq, iptables, rsync, squashfs-tools, attr, acl, shadow

## systemd Services

- `incus.service` - Main daemon (auto-enabled)
- `incus.socket` - Unix socket activation

The daemon creates the `incus-admin` group at install time. Add users to
this group to grant non-root access to the Incus API.

## Notes

- **Memory**: QEMU needs at least 2GB (`-m 2048`), 4GB recommended
- **KVM**: Not required but improves VM performance if `/dev/kvm` is available
- **AppArmor**: Optional, works without it (warning at startup is harmless)
- **VM support**: Requires QEMU on the target (optional, containers work without it)
- **Networking**: The default bridge (`incusbr0`) is created by `incus admin init`
- **Images**: The `images:` remote points to images.linuxcontainers.org
- **Clustering**: Supported via cowsql; use `incus admin init` interactive mode to configure

## Updating Go Dependencies

The Go module dependencies are managed via go-mod-discovery:

```shell
bitbake incus -c discover_and_generate
```

This regenerates the `go-mod-*.inc` files in this directory.
