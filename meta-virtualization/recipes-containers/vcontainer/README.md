# vdkr & vpdmn - Emulated Docker/Podman for Cross-Architecture

Execute Docker or Podman commands inside a QEMU-emulated target environment.

| Tool | Runtime | State Directory |
|------|---------|-----------------|
| `vdkr` | Docker (dockerd + containerd) | `~/.vdkr/<arch>/` |
| `vpdmn` | Podman (daemonless) | `~/.vpdmn/<arch>/` |

## Quick Start

```bash
# Build and install SDK (see "Standalone SDK" section for full instructions)
MACHINE=qemux86-64 bitbake vcontainer-tarball
./tmp/deploy/sdk/vcontainer-standalone.sh -d /tmp/vcontainer -y
source /tmp/vcontainer/init-env.sh

# List images (uses host architecture by default)
vdkr images

# Explicit architecture
vdkr -a aarch64 images

# Import an OCI container
vdkr vimport ./my-container-oci/ myapp:latest

# Export storage for deployment
vdkr --storage /tmp/docker-storage.tar vimport ./container-oci/ myapp:latest

# Clean persistent state
vdkr clean
```

## Architecture Selection

vdkr detects the target architecture automatically. Override with:

| Method | Example | Priority |
|--------|---------|----------|
| `--arch` / `-a` flag | `vdkr -a aarch64 images` | Highest |
| Executable name | `vdkr-x86_64 images` | 2nd |
| `VDKR_ARCH` env var | `export VDKR_ARCH=aarch64` | 3rd |
| Config file | `~/.config/vdkr/arch` | 4th |
| Host architecture | `uname -m` | Lowest |

**Set default architecture:**
```bash
mkdir -p ~/.config/vdkr
echo "aarch64" > ~/.config/vdkr/arch
```

**Backwards-compatible symlinks:**
```bash
vdkr-aarch64 images   # Same as: vdkr -a aarch64 images
vdkr-x86_64 images    # Same as: vdkr -a x86_64 images
```

## Commands

### Docker-Compatible (same syntax as Docker)

| Command | Description |
|---------|-------------|
| `images` | List images |
| `run [opts] <image> [cmd]` | Run a command in a container |
| `import <tarball> [name:tag]` | Import rootfs tarball |
| `load -i <file>` | Load Docker image archive |
| `save -o <file> <image>` | Save image to archive |
| `pull <image>` | Pull image from registry |
| `tag <source> <target>` | Tag an image |
| `rmi <image>` | Remove an image |
| `ps`, `rm`, `logs`, `start`, `stop` | Container management |
| `exec [opts] <container> <cmd>` | Execute in running container |

### Extended Commands (vdkr-specific)

| Command | Description |
|---------|-------------|
| `vimport <path> [name:tag]` | Import OCI directory, tarball, or directory (auto-detect) |
| `vrun [opts] <image> [cmd]` | Run with entrypoint cleared (command runs directly) |
| `clean` | Remove persistent state |
| `memres start [-p port:port]` | Start memory resident VM with optional port forwards |
| `memres stop` | Stop memory resident VM |
| `memres restart [--clean]` | Restart VM (optionally clean state) |
| `memres status` | Show memory resident VM status |
| `memres list` | List all running memres instances |

### run vs vrun

| Command | Behavior |
|---------|----------|
| `run` | Docker-compatible - entrypoint honored |
| `vrun` | Clears entrypoint when command given - runs command directly |

## Options

| Option | Description |
|--------|-------------|
| `--arch, -a <arch>` | Target architecture (x86_64 or aarch64) |
| `--instance, -I <name>` | Use named instance (shortcut for `--state-dir ~/.vdkr/<name>`) |
| `--stateless` | Don't use persistent state |
| `--storage <file>` | Export Docker storage to tar after command |
| `--state-dir <path>` | Override state directory |
| `--no-kvm` | Disable KVM acceleration |
| `-v, --verbose` | Enable verbose output |

## Memory Resident Mode

Keep QEMU VM running for fast command execution (~1s vs ~30s):

```bash
vdkr memres start              # Start daemon
vdkr images                    # Fast!
vdkr pull alpine:latest        # Fast!
vdkr run -it alpine /bin/sh    # Interactive mode works via daemon!
vdkr memres stop               # Stop daemon
```

Interactive mode (`run -it`, `vrun -it`, `exec -it`) now works directly via the daemon using virtio-serial passthrough - no need to stop/restart the daemon.

Note: Interactive mode combined with volume mounts (`-v`) still requires stopping the daemon temporarily.

## Port Forwarding

Forward ports from host to containers for SSH, web servers, etc:

```bash
# Start daemon with port forwarding
vdkr memres start -p 8080:80           # Host:8080 -> Guest:80
vdkr memres start -p 8080:80 -p 2222:22  # Multiple ports

# Run container with host networking (shares guest's network)
vdkr run -d --rm --network=host nginx:alpine

# Access from host
curl http://localhost:8080              # Access nginx
```

**How it works:**
```
Host:8080 → (QEMU hostfwd) → Guest:80 → (--network=host) → Container on port 80
```

Containers must use `--network=host` because Docker runs with `--bridge=none` inside the guest. This means the container shares the guest VM's network stack directly.

**Options:**
- `-p <host_port>:<guest_port>` - TCP forwarding (default)
- `-p <host_port>:<guest_port>/udp` - UDP forwarding
- Multiple `-p` options can be specified

**Managing instances:**
```bash
vdkr memres list                        # Show all running instances
vdkr memres start -p 9000:80            # Prompts if instance already running
vdkr -I web memres start -p 8080:80     # Start named instance "web"
vdkr -I web images                      # Use named instance
vdkr -I backend run -d --network=host my-api:latest
```

## Exporting Images

Two ways to export, for different purposes:

```bash
# Export a single image as Docker archive (portable, can be `docker load`ed)
vdkr save -o /tmp/myapp.tar myapp:latest

# Export entire Docker storage for deployment to target rootfs
vdkr --storage /tmp/docker-storage.tar images
```

| Method | Output | Use case |
|--------|--------|----------|
| `save -o file image:tag` | Docker archive | Share image, load on another Docker |
| `--storage file` | `/var/lib/docker` tar | Deploy to target rootfs |

## Persistent State

By default, Docker state persists in `~/.vdkr/<arch>/`. Images imported in one session are available in the next.

```bash
vdkr vimport ./container-oci/ myapp:latest
vdkr images   # Shows myapp:latest

# Later...
vdkr images   # Still shows myapp:latest

# Start fresh
vdkr --stateless images   # Empty

# Clear state
vdkr clean
```

## Standalone SDK

Create a self-contained redistributable SDK that works without Yocto:

```bash
# Ensure multiconfig is enabled in local.conf:
# BBMULTICONFIG = "vruntime-aarch64 vruntime-x86-64"

# Step 1: Build blobs for desired architectures (sequentially to avoid deadlocks)
bitbake mc:vruntime-x86-64:vdkr-initramfs-create mc:vruntime-x86-64:vpdmn-initramfs-create
bitbake mc:vruntime-aarch64:vdkr-initramfs-create mc:vruntime-aarch64:vpdmn-initramfs-create

# Step 2: Build SDK (auto-detects available architectures)
MACHINE=qemux86-64 bitbake vcontainer-tarball

# Output: tmp/deploy/sdk/vcontainer-standalone.sh
```

To limit architectures, set in local.conf:
```bash
VCONTAINER_ARCHITECTURES = "x86_64"           # x86_64 only
VCONTAINER_ARCHITECTURES = "aarch64"          # aarch64 only
VCONTAINER_ARCHITECTURES = "x86_64 aarch64"   # both (default if both built)
```

The SDK includes:
- `vdkr`, `vpdmn` - Main CLI scripts
- `vdkr-<arch>`, `vpdmn-<arch>` - Symlinks for each included architecture
- `vrunner.sh` - Shared QEMU runner
- `vdkr-blobs/`, `vpdmn-blobs/` - Kernel and initramfs per architecture
- `sysroots/` - SDK binaries (QEMU, socat, libraries)
- `init-env.sh` - Environment setup script

Usage:
```bash
# Install (self-extracting)
./vcontainer-standalone.sh -d /tmp/vcontainer -y

# Or extract tarball directly
tar -xf vcontainer-standalone.tar.xz -C /tmp/vcontainer

# Use
cd /tmp/vcontainer
source init-env.sh
vdkr-x86_64 images
vdkr-aarch64 images
```

## Interactive Mode

Run containers with an interactive shell:

```bash
# Interactive shell in a container
vdkr run -it alpine:latest /bin/sh

# Using vrun (clears entrypoint)
vdkr vrun -it alpine:latest /bin/sh

# Inside the container:
/ # apk add curl
/ # exit
```

## Networking

vdkr supports outbound networking via QEMU's slirp user-mode networking:

```bash
# Pull an image from a registry
vdkr pull alpine:latest

# Images persist in state directory
vdkr images   # Shows alpine:latest
```

## Registry Login and Configuration

For authenticated registries:

```bash
# Login (interactive password prompt)
vdkr login --username myuser https://registry.example.com/

# Pull from the registry
vdkr pull registry.example.com/myimage:latest
```

Set a default registry so you don't need to specify the full URL each time:

```bash
# Set default registry (persisted across sessions)
vdkr vconfig registry registry.example.com

# Now pulls try the default registry first, then Docker Hub
vdkr pull myimage:latest

# One-off override without changing the default
vdkr --registry other.registry.com pull myimage:latest

# Clear default registry
vdkr vconfig registry --reset
```

**Note:** The `--registry` flag is a vdkr option that sets the default
registry for pulls. For `login`, pass the registry URL as a positional
argument after the login flags:

```bash
# Correct:
vdkr login --username myuser https://registry.example.com/

# Wrong (--registry is consumed by vdkr, login gets no URL):
vdkr --registry https://registry.example.com/ login --username myuser
```

**TLS certificates:** The vdkr/vpdmn rootfs images include common
intermediate certificates (Let's Encrypt E8/R11) to handle registries
that don't send the full certificate chain. For self-signed registries,
use `--secure-registry --ca-cert`:

```bash
vdkr --secure-registry --ca-cert /path/to/ca.crt pull myimage
```

### Passing an existing docker/podman auth file (`--config`)

If you already have credentials set up on the host (for example, from
running `docker login` locally), you can pass the resulting auth file
straight through into the emulated environment instead of re-entering
credentials with `--registry-user`/`--registry-pass`:

```bash
# Docker (vdkr): uses ~/.docker/config.json by default
vdkr --config ~/.docker/config.json pull registry.example.com/myimage

# Podman (vpdmn): uses $XDG_RUNTIME_DIR/containers/auth.json
vpdmn --config $XDG_RUNTIME_DIR/containers/auth.json pull registry.example.com/myimage
```

The path can also be supplied via environment:

```bash
export VDKR_CONFIG=$HOME/.docker/config.json
vdkr pull registry.example.com/myimage
```

(`VPDMN_CONFIG` is honoured identically by `vpdmn`.)

**What the file ends up as inside the VM:**

| Tool  | Target path                       | Notes                                             |
| ----- | --------------------------------- | ------------------------------------------------- |
| vdkr  | `/root/.docker/config.json`       | Mode 0600; containing dir 0700                    |
| vpdmn | `/run/containers/0/auth.json`     | Mode 0600; `$REGISTRY_AUTH_FILE` exported         |

**Security model.** The credential file is treated as secret material:

- The host-side file **must** be a regular file with mode `0600` or `0400`.
  World/group-readable files are rejected outright. Symlinks are rejected.
  Files larger than 1 MiB are rejected.
- On the host it is copied into a per-invocation private directory under
  `$TMPDIR/vdkr-$$/auth_share` (mode 0700; file mode 0400) and removed
  automatically by the `EXIT`/`INT`/`TERM` trap when `vrunner.sh` exits.
- It is exposed to the guest on a **dedicated** virtio-9p share whose
  mount tag (`vdkr_auth` / `vpdmn_auth`) is distinct from the general
  `*_share` share used for input/output. The guest mounts it **read-only**
  at `/mnt/auth`, copies it into the runtime's credential location, then
  **unmounts** `/mnt/auth` so nothing in the VM retains an open reference
  to the host staging directory.
- Nothing about the file appears on the kernel command line. Only a
  boolean flag (`docker_auth=1` / `podman_auth=1`) is passed so the guest
  init script knows to look on the auth share.
- When both `--config` and `--registry-user`/`--registry-pass` are
  supplied, `--config` wins and a NOTE is logged.
- `--config` is NOT forwarded into container workloads (it only reaches
  the container engine's credential store); containers themselves never
  see `/mnt/auth`.

## Volume Mounts

Mount host directories into containers using `-v` (requires memory resident mode):

```bash
# Start memres first
vdkr memres start

# Mount a host directory
vdkr vrun -v /tmp/data:/data alpine cat /data/file.txt

# Mount multiple directories
vdkr vrun -v /home/user/src:/src -v /tmp/out:/out alpine /src/build.sh

# Read-only mount
vdkr vrun -v /etc/config:/config:ro alpine cat /config/settings.conf

# With run command (same syntax)
vdkr run -v ./local:/app --rm myapp:latest /app/run.sh
```

**How it works:**
- Host files are copied to the virtio-9p share directory before container runs
- Container accesses them via the shared filesystem mount
- For `:rw` mounts (default), changes are synced back to host after container exits
- For `:ro` mounts, changes in container are discarded

**Limitations:**
- Requires daemon mode (memres) - volume mounts don't work in regular mode
- Interactive + volumes (`-it -v`) requires stopping daemon temporarily (share directory conflict)
- Changes sync after container exits (not real-time)
- Large directories may be slow to copy

**Debugging with volumes:**
```bash
# Run non-interactively with a shell command to inspect volume contents
vdkr vrun -v /tmp/data:/data alpine ls -la /data

# Or start the container detached and exec into it
vdkr run -d --name debug -v /tmp/data:/data alpine sleep 3600
vdkr exec debug ls -la /data
vdkr rm -f debug
```

## Testing

See `tests/README.md` for the pytest-based test suite:

```bash
# Build and install SDK
MACHINE=qemux86-64 bitbake vcontainer-tarball
./tmp/deploy/sdk/vcontainer-standalone.sh -d /tmp/vcontainer -y

# Run tests
cd /opt/bruce/poky/meta-virtualization
pytest tests/test_vdkr.py -v --vdkr-dir /tmp/vcontainer
```

## vpdmn (Podman)

vpdmn provides the same functionality as vdkr but uses Podman instead of Docker:

```bash
# Pull and run with Podman
vpdmn-x86_64 pull alpine:latest
vpdmn-x86_64 vrun alpine:latest echo hello

# Override entrypoint
vpdmn-x86_64 run --rm --entrypoint /bin/cat alpine:latest /etc/os-release

# Import OCI container
vpdmn-x86_64 vimport ./my-container-oci/ myapp:latest
```

Key differences from vdkr:
- **Daemonless** - No containerd/dockerd startup, faster boot (~5s vs ~10-15s)
- **Separate state** - Uses `~/.vpdmn/<arch>/` (images not shared with vdkr)
- **Same commands** - `images`, `pull`, `run`, `vrun`, `vimport`, etc. all work

## Recipes

| Recipe | Purpose |
|--------|---------|
| `vcontainer-tarball.bb` | Standalone SDK with vdkr and vpdmn |
| `vdkr-initramfs-create_1.0.bb` | Build vdkr initramfs blobs |
| `vpdmn-initramfs-create_1.0.bb` | Build vpdmn initramfs blobs |

## Files

| File | Purpose |
|------|---------|
| `vdkr.sh` | Docker CLI wrapper |
| `vpdmn.sh` | Podman CLI wrapper |
| `vrunner.sh` | Shared QEMU runner script |
| `vdkr-init.sh` | Docker init script (baked into initramfs) |
| `vpdmn-init.sh` | Podman init script (daemonless) |

## Testing Both Tools

```bash
# Build and install SDK (includes both vdkr and vpdmn)
MACHINE=qemux86-64 bitbake vcontainer-tarball
./tmp/deploy/sdk/vcontainer-standalone.sh -d /tmp/vcontainer -y

# Run tests for both tools
cd /opt/bruce/poky/meta-virtualization
pytest tests/test_vdkr.py tests/test_vpdmn.py -v --vdkr-dir /tmp/vcontainer
```

## See Also

- `classes/container-cross-install.bbclass` for bundling containers into Yocto images
- `classes/container-bundle.bbclass` for creating container bundle packages
- `tests/README.md` for test documentation
