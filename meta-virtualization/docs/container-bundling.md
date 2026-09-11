Container Bundling and Cross-Architecture Deployment
=====================================================

This document describes how to bundle containers into Yocto images at build
time using the container-cross-install system. This enables deploying Docker
and Podman containers from x86_64 build systems to ARM64/x86_64 targets
without requiring container runtimes on the build host.

Prerequisites
-------------

Enable the vcontainer distro feature in local.conf:

    DISTRO_FEATURES:append = " virtualization vcontainer"

Enable multiconfig for blob builds:

    BBMULTICONFIG = "vruntime-aarch64 vruntime-x86-64"


Choosing How to Bundle Containers
---------------------------------

There are two ways to bundle containers into a host image:

1. **BUNDLED_CONTAINERS variable** (simpler, no extra recipe needed)

       # In local.conf or image recipe
       BUNDLED_CONTAINERS = "container-base:docker myapp-container:docker:autostart"

2. **container-bundle packages** (more flexible)

       # Create a bundle recipe, then add to IMAGE_INSTALL
       inherit container-bundle
       CONTAINER_BUNDLES = "myapp-container:autostart"

### Decision Guide

    Use Case                                    | BUNDLED_CONTAINERS | Bundle Recipe
    --------------------------------------------|--------------------|--------------
    Simple: containers in one host image        | recommended        | overkill
    Reuse containers across multiple images     | repetitive         | recommended
    Remote containers (docker.io/library/...)   | not supported      | required
    Package versioning and dependencies         | not supported      | supported
    Distribute pre-built container set          | not supported      | supported

**For most single-image use cases, BUNDLED_CONTAINERS is simpler:**
- No bundle recipe needed
- Dependencies auto-generated at parse time
- vrunner batch-import runs once for all containers

**Use container-bundle.bbclass when you need:**
- Remote container fetching via skopeo
- A distributable/versioned package of containers
- To share the same bundle across multiple different host images


Component Relationships
-----------------------

To bundle a local container like "myapp:autostart", three recipe types
work together:

1. **Application Recipe** (builds the software)

       recipes-demo/myapp/myapp_1.0.bb
       - Compiles application binaries
       - Creates installable package (myapp)

2. **Container Image Recipe** (creates OCI image containing the app)

       recipes-demo/images/myapp-container.bb
       - inherit image image-oci
       - IMAGE_INSTALL = "myapp"
       - Produces: ${DEPLOY_DIR_IMAGE}/myapp-container-latest-oci/

3. **Bundle Recipe** (packages container images for deployment) - OPTIONAL

       recipes-demo/bundles/my-bundle_1.0.bb
       - inherit container-bundle
       - CONTAINER_BUNDLES = "myapp-container:autostart"
       - Creates installable package with OCI data

### Flow Diagram

    myapp_1.0.bb                    myapp-container.bb
    (application)                   (container image)
         │                               │
         │ IMAGE_INSTALL="myapp"         │ inherit image-oci
         └──────────────┬────────────────┘
                        │
                        ▼
               myapp-container-latest-oci/
               (OCI directory in DEPLOY_DIR_IMAGE)
                        │
                        │ BUNDLED_CONTAINERS or CONTAINER_BUNDLES
                        ▼
               container-image-host
               (target host image with containers pre-installed)

### Concrete Example (from meta-virtualization)

- Application: `recipes-demo/autostart-test/autostart-test_1.0.bb`
- Container image: `recipes-demo/images/autostart-test-container.bb`
- Usage: `BUNDLED_CONTAINERS = "autostart-test-container:docker:autostart"`


OCI Multi-Layer Images
----------------------

By default, OCI images are single-layer (the entire rootfs in one layer).
Multi-layer images enable:
- Shared base layers across images
- Faster rebuilds via layer caching
- Smaller delta updates when only app layer changes

### Layer Modes

| Mode | Variable | Layers | Use Case |
|------|----------|--------|----------|
| Single | (default) | 1 | Simple containers, backward compat |
| Two-layer | `OCI_BASE_IMAGE` | 2 | Base + app (shared base across images) |
| Multi-layer | `OCI_LAYER_MODE="multi"` | 3+ | Fine-grained layers (base, deps, app) |

### Two-Layer Mode (OCI_BASE_IMAGE)

Build on top of another OCI image recipe:

    # myapp-container.bb
    inherit image image-oci
    OCI_BASE_IMAGE = "container-base"
    IMAGE_INSTALL = "base-files busybox myapp"

Result: 2 layers (container-base layer + myapp layer)

| OCI_BASE_IMAGE Value | Description |
|----------------------|-------------|
| Recipe name | `"container-base"` - uses OCI output from another recipe |
| Absolute path | `"/path/to/oci-dir"` - uses existing OCI layout |

For external images (docker.io, quay.io), use `container-bundle` with
`CONTAINER_BUNDLE_DEPLOY = "1"` to fetch and deploy them first.

### Multi-Layer Mode (OCI_LAYERS)

Create explicit layers with fine-grained control:

    # app-container-multilayer.bb
    inherit image image-oci

    OCI_LAYER_MODE = "multi"
    OCI_LAYERS = "\
        base:packages:base-files+base-passwd+netbase \
        shell:packages:busybox \
        app:packages:curl \
    "

Result: 3 layers (base, shell, app)

Packages named in any `packages:` layer are automatically folded into
`IMAGE_INSTALL`, so do_rootfs's recrdeptask builds them. You do not
need to repeat the package list in `IMAGE_INSTALL`. If a recipe needs
additional packages that aren't part of any final layer (e.g. for a
rootfs-only postprocess fixup), it can still add to `IMAGE_INSTALL`
itself — the auto-derivation is additive.

#### Layer Definition Format

    name:type:content

| Type | Content Format | Description |
|------|----------------|-------------|
| `packages` | `pkg1+pkg2+pkg3` | Install packages (use + delimiter) |
| `directories` | `/path1+/path2` | Copy directories from IMAGE_ROOTFS |
| `files` | `/file1+/file2` | Copy specific files from IMAGE_ROOTFS |
| `host` | `src:dst+src:dst` | Copy from build machine (sparingly — see below) |

#### Example Recipes

**Three-layer with explicit packages:**
```bitbake
OCI_LAYER_MODE = "multi"
OCI_LAYERS = "\
    base:packages:base-files+base-passwd+netbase \
    python:packages:python3+python3-pip \
    app:directories:/opt/myapp \
"
```

**Two-layer with base image + multi-layer app:**
```bitbake
OCI_BASE_IMAGE = "container-base"
OCI_LAYER_MODE = "multi"
OCI_LAYERS = "\
    deps:packages:python3+python3-pip \
    app:directories:/opt/myapp \
"
```

#### Conditional Packages per Layer

Use `${@bb.utils.contains(...)}` directly inside a layer's package list
to add or omit packages based on `PACKAGECONFIG` (or any other
distro/recipe variable) without duplicating the whole `OCI_LAYERS`
declaration in two branches:

```bitbake
PACKAGECONFIG ??= ""
PACKAGECONFIG[dev] = ""

OCI_LAYER_MODE = "multi"
OCI_LAYERS = "\
    base:packages:base-files+base-passwd+netbase \
    python:packages:python3+coreutils${@bb.utils.contains('PACKAGECONFIG', 'dev', '+python3-pip', '', d)} \
"
```

The expression expands to `+python3-pip` when `dev` is enabled and to
nothing otherwise. Because the `+` delimiter is folded into the
substituted text, the resulting layer string is well-formed in both
cases (`python3+coreutils` or `python3+coreutils+python3-pip`).

This composes with the auto-derivation above: `python3-pip` is added to
`IMAGE_INSTALL` only when the `dev` config is active, exactly as if you
had written it out by hand.

### Layer Caching

Multi-layer builds cache pre-installed package layers for faster rebuilds.
Installing packages requires configuring the package manager, resolving
dependencies, and running post-install scripts - this is slow. Caching
saves the fully-installed layer rootfs after the first build so subsequent
builds can skip package installation entirely.

#### Configuration

    # Enabled by default
    OCI_LAYER_CACHE ?= "1"
    OCI_LAYER_CACHE_DIR ?= "${TOPDIR}/oci-layer-cache/${MACHINE}"

#### Cache Key Components

The cache key is a SHA256 hash of:

| Component | Why It Matters |
|-----------|----------------|
| Layer name | Different layers cached separately |
| Layer type | `packages` vs `directories` vs `files` |
| Package list (sorted) | Adding/removing packages invalidates cache |
| Package versions | Upgrading a package invalidates cache |
| MACHINE, TUNE_PKGARCH | Architecture-specific packages |

#### Advantages

**Faster rebuilds**: Subsequent builds restore cached layers in ~1 second
instead of ~10-30 seconds per layer for package installation.

**Efficient development**: When only your app layer changes, base and
dependency layers are restored from cache:

    OCI_LAYERS = "\
        base:packages:base-files+busybox \      # Cached - stable
        deps:packages:python3+python3-pip \     # Cached - stable
        app:packages:myapp \                    # Rebuilt - changes often
    "

**Automatic invalidation**: Cache invalidates when packages change version,
layers are modified, or architecture changes. No manual clearing needed.

**Shared across recipes**: Cache stored in `${TOPDIR}/oci-layer-cache/` so
recipes with identical layers share the same cached content.

#### Build Log Example

    # First build - cache misses
    NOTE: OCI Cache MISS: Layer 'base' (base:base-files=3.0.14 ...)
    NOTE: OCI Cache: Saving layer 'base' to cache (be88c180f651416b)
    NOTE: OCI: Pre-installed packages for 3 layers (cache: 0 hits, 3 misses)

    # Second build - cache hits
    NOTE: OCI Cache HIT: Layer 'base' (be88c180f651416b)
    NOTE: OCI: Pre-installed packages for 3 layers (cache: 3 hits, 0 misses)

#### When to Disable

Disable caching with `OCI_LAYER_CACHE = "0"` if you:
- Suspect cache corruption
- Need fully reproducible builds with no local state
- Are debugging package installation issues

### OCI_IMAGE_CMD vs OCI_IMAGE_ENTRYPOINT

    # CMD (default) - replaced when user passes arguments
    OCI_IMAGE_CMD = "/bin/sh"
    # docker run image           → /bin/sh
    # docker run image /bin/bash → /bin/bash

    # ENTRYPOINT - always runs, args appended
    OCI_IMAGE_ENTRYPOINT = "curl"
    OCI_IMAGE_ENTRYPOINT_ARGS = "http://localhost"
    # docker run image           → curl http://localhost
    # docker run image google.com → curl google.com

Use CMD for base images (flexible). Use ENTRYPOINT for wrapper tools.

### Verifying Layer Count

    # Check layer count with skopeo
    skopeo inspect oci:tmp/deploy/images/qemux86-64/myapp-latest-oci | jq '.Layers | length'

### Testing Multi-Layer OCI

    cd /opt/bruce/poky/meta-virtualization

    # Quick tests (no builds)
    pytest tests/test_multilayer_oci.py -v -k "not slow"

    # Full tests (with builds)
    pytest tests/test_multilayer_oci.py -v --poky-dir /opt/bruce/poky


Using BUNDLED_CONTAINERS
------------------------

Set in local.conf or image recipe:

    BUNDLED_CONTAINERS = "container-base:docker myapp-container:podman:autostart"

### Format

    name:runtime[:autostart][:external]

- **name**: Container image recipe name or OCI directory name
- **runtime**: `docker` or `podman`
- **autostart**: Optional - `autostart`, `always`, `unless-stopped`, `on-failure`
- **external**: Optional - skip dependency generation for third-party blobs

### Examples

    # Yocto-built containers (dependencies auto-generated)
    BUNDLED_CONTAINERS = "container-base:docker"
    BUNDLED_CONTAINERS = "myapp-container:podman:autostart"

    # Third-party blobs (no dependency generated)
    BUNDLED_CONTAINERS = "vendor-image:docker:external"

    # Legacy format (still supported)
    BUNDLED_CONTAINERS = "container-base-latest-oci:docker"


Using container-bundle.bbclass
------------------------------

Create a bundle recipe:

    # recipes-demo/bundles/my-bundle_1.0.bb
    inherit container-bundle

    CONTAINER_BUNDLES = "\
        myapp-container:autostart \
        mydb-container \
        docker.io/library/redis:7 \
    "

    # Required for remote containers:
    CONTAINER_DIGESTS[docker.io_library_redis_7] = "sha256:..."

To get the digest for a remote container, use skopeo:

    skopeo inspect docker://docker.io/library/redis:7 | jq -r '.Digest'

Install in your host image:

    IMAGE_INSTALL:append:pn-container-image-host = " my-bundle"


Acknowledging Third-Party Container Licenses
--------------------------------------------

Every fetch of a remote container emits a build-time warning to remind
integrators that they are shipping content they did not build from source:

    WARNING: Fetching third-party container: docker.io/library/alpine
             Ensure you have rights to redistribute this container in your
             image. Check the container's license terms before distribution.
             To acknowledge this container and silence this warning
             (downgrades to a bb.note for build-log/SBOM audit), add to
             local.conf or your distro config:
               CONTAINER_FLAGS_ACCEPTED += "docker.io/library/alpine"

Once you have reviewed the container's license and confirmed redistribution
rights, add the URL to `CONTAINER_FLAGS_ACCEPTED` in `local.conf` or your
distro config:

    CONTAINER_FLAGS_ACCEPTED += "docker.io/library/alpine"
    CONTAINER_FLAGS_ACCEPTED += "docker.io/library/busybox"

Subsequent builds demote the warning to a `bb.note`, which is suppressed
from normal build output but still recorded in `bitbake-cookerdaemon.log`
and the recipe's task log:

    NOTE: Fetching third-party container (license acknowledged via
          CONTAINER_FLAGS_ACCEPTED): docker.io/library/alpine

The note is intentionally not silent — it preserves the audit trail for
SBOM tools and distro release reviews while removing the visible
"WARNING" line from clean builds.

### Matching rules

- URLs in `CONTAINER_FLAGS_ACCEPTED` are matched against both the full URL
  (with `:tag` or `@digest`) and the bare URL with tag/digest stripped.
  Accepting `docker.io/library/alpine` covers `alpine:3.19`, `alpine:3.20`,
  any `alpine@sha256:...`, etc.
- The `*` wildcard accepts every third-party container in the build.
  Convenient for distros that have a standing license-review process,
  riskier as a casual opt-in.

### Where to set it

Acknowledgement belongs in the **integration layer** — `local.conf`,
distro config, or an image recipe that gathers multiple bundles. Recipe
authors should not pre-accept the containers their own recipe bundles;
that defeats the warning's purpose by hiding the license question from
the integrator who has to make the call.


Container Autostart
-------------------

Containers can be configured to start automatically on boot:

| Policy | Description |
|--------|-------------|
| `autostart` | Alias for unless-stopped (recommended) |
| `always` | Always restart container |
| `unless-stopped` | Restart unless manually stopped |
| `on-failure` | Restart only on non-zero exit code |

**Generated files:**
- Docker: `/lib/systemd/system/container-<name>.service`
- Podman: `/etc/containers/systemd/<name>.container` (Quadlet format)


Custom Service Files
--------------------

For containers that require specific startup configuration (ports, volumes,
capabilities, dependencies), you can provide custom service files instead of
using the auto-generated ones.

### Variable Format

Use the `CONTAINER_SERVICE_FILE` varflag to specify custom service files:

    CONTAINER_SERVICE_FILE[container-name] = "${UNPACKDIR}/myservice.service"
    CONTAINER_SERVICE_FILE[other-container] = "${UNPACKDIR}/other.container"

### For BUNDLED_CONTAINERS (in image recipe)

    # host-image.bb or local.conf
    inherit container-cross-install

    SRC_URI += "\
        file://myapp.service \
        file://mydb.container \
    "

    BUNDLED_CONTAINERS = "\
        myapp-container:docker:autostart \
        mydb-container:podman:autostart \
    "

    # Map containers to custom service files
    CONTAINER_SERVICE_FILE[myapp-container] = "${UNPACKDIR}/myapp.service"
    CONTAINER_SERVICE_FILE[mydb-container] = "${UNPACKDIR}/mydb.container"

### For container-bundle Packages

    # my-bundle_1.0.bb
    inherit container-bundle

    SRC_URI = "\
        file://myapp.service \
        file://mydb.container \
    "

    CONTAINER_BUNDLES = "\
        myapp-container:autostart \
        mydb-container:autostart \
    "

    CONTAINER_SERVICE_FILE[myapp-container] = "${UNPACKDIR}/myapp.service"
    CONTAINER_SERVICE_FILE[mydb-container] = "${UNPACKDIR}/mydb.container"

### Docker .service Example

    # myapp.service
    [Unit]
    Description=MyApp Container
    After=docker.service
    Requires=docker.service

    [Service]
    Type=simple
    Restart=unless-stopped
    RestartSec=5s
    ExecStartPre=-/usr/bin/docker rm -f myapp
    ExecStart=/usr/bin/docker run --rm --name myapp \
        -p 8080:80 \
        -v /data/myapp:/var/lib/myapp:rw \
        --cap-add NET_ADMIN \
        myapp:latest
    ExecStop=/usr/bin/docker stop myapp

    [Install]
    WantedBy=multi-user.target

### Podman .container (Quadlet) Example

    # mydb.container
    [Unit]
    Description=MyDB Container

    [Container]
    Image=mydb:latest
    ContainerName=mydb
    PublishPort=5432:5432
    Volume=/data/db:/var/lib/postgresql/data:Z
    Environment=POSTGRES_PASSWORD=secret

    [Service]
    Restart=unless-stopped
    RestartSec=5s

    [Install]
    WantedBy=multi-user.target


vdkr and vpdmn - Virtual Container Runtimes
===========================================

vdkr (virtual docker) and vpdmn (virtual podman) are tools that execute
container commands inside a QEMU-emulated environment. They enable
cross-architecture container operations during Yocto builds.

| Tool | Runtime | State Directory |
|------|---------|-----------------|
| `vdkr` | Docker (dockerd + containerd) | `~/.vdkr/<arch>/` |
| `vpdmn` | Podman (daemonless) | `~/.vpdmn/<arch>/` |

Quick Start
-----------

    # Build and install the standalone SDK
    MACHINE=qemux86-64 bitbake vcontainer-tarball
    ./tmp/deploy/sdk/vcontainer-standalone.sh -d /tmp/vcontainer -y
    source /tmp/vcontainer/init-env.sh

    # List images
    vdkr images

    # Import an OCI container
    vdkr vimport ./my-container-oci/ myapp:latest

    # Export storage for deployment
    vdkr --storage /tmp/docker-storage.tar vimport ./container-oci/ myapp:latest

    # Clean persistent state
    vdkr clean

Architecture Selection
----------------------

vdkr/vpdmn detect target architecture automatically. Override with:

| Method | Example | Priority |
|--------|---------|----------|
| `--arch` / `-a` flag | `vdkr -a aarch64 images` | Highest |
| Executable name | `vdkr-x86_64 images` | 2nd |
| `VDKR_ARCH` env var | `export VDKR_ARCH=aarch64` | 3rd |
| Config file | `~/.config/vdkr/arch` | 4th |
| Host architecture | `uname -m` | Lowest |

Memory Resident Mode
--------------------

Keep QEMU VM running for fast command execution (~1s vs ~30s):

    vdkr vmemres start              # Start daemon
    vdkr images                    # Fast!
    vdkr pull alpine:latest        # Fast!
    vdkr vmemres stop               # Stop daemon

Commands
--------

### Docker-Compatible

    images, run, import, load, save, pull, tag, rmi, ps, rm, logs, start, stop, exec

### Extended (vdkr-specific)

| Command | Description |
|---------|-------------|
| `vimport <path> [name:tag]` | Import OCI directory or tarball |
| `vrun [opts] <image> [cmd]` | Run with entrypoint cleared |
| `vshell` | Open interactive shell inside VM (requires vmemres) |
| `clean` | Remove persistent state |
| `vmemres start/stop/status` | Memory resident VM control |


How It Works
============

The container-cross-install system uses QEMU to run container tools
(Docker/Podman) for the target architecture during the build. This solves
the "pseudo problem" where container tools fail under Yocto's fakeroot.

Architecture:

    ┌─────────────────────────────────────────────────────────────────┐
    │  QEMU VM (target architecture)                                  │
    │  ┌───────────────────────────────────────────────────────────┐  │
    │  │  rootfs.img (squashfs, ~100-130MB)                        │  │
    │  │  - Docker or Podman tools                                 │  │
    │  │  - Processes OCI containers                               │  │
    │  │  - Outputs storage tar via console                        │  │
    │  └───────────────────────────────────────────────────────────┘  │
    │                                                                 │
    │  Drive Layout:                                                  │
    │    /dev/vda = rootfs.img (tools)                               │
    │    /dev/vdb = input disk (OCI containers)                      │
    │    /dev/vdc = state disk (Docker/Podman storage)               │
    └─────────────────────────────────────────────────────────────────┘

Blobs are built via multiconfig and deployed to:

    tmp-vruntime-aarch64/deploy/images/qemuarm64/vdkr/
    tmp-vruntime-x86-64/deploy/images/qemux86-64/vdkr/


Testing
=======

    cd /opt/bruce/poky/meta-virtualization
    
    # Run container-cross-install tests
    pytest tests/test_container_cross_install.py -v
    
    # Run vdkr/vpdmn CLI tests
    pytest tests/test_vdkr.py tests/test_vpdmn.py -v --vdkr-dir /tmp/vcontainer


Quick Reference Commands
========================

Build host image with bundled containers:

    cd /opt/bruce/poky
    source oe-init-build-env build

    # Ensure local.conf has:
    #   DISTRO_FEATURES:append = " virtualization vcontainer"
    #   BBMULTICONFIG = "vruntime-aarch64 vruntime-x86-64"
    #   BUNDLED_CONTAINERS = "container-base:docker autostart-test-container:docker:autostart"

    MACHINE=qemux86-64 bitbake container-image-host

Build the vdkr/vpdmn SDK tarball:

    # Build blobs for desired architectures (sequentially to avoid deadlocks)
    bitbake mc:vruntime-x86-64:vdkr-initramfs-create mc:vruntime-x86-64:vpdmn-initramfs-create
    bitbake mc:vruntime-aarch64:vdkr-initramfs-create mc:vruntime-aarch64:vpdmn-initramfs-create

    # Build SDK tarball
    MACHINE=qemux86-64 bitbake vcontainer-tarball

    # Output: tmp/deploy/sdk/vcontainer-standalone.sh

Install and test SDK:

    ./tmp/deploy/sdk/vcontainer-standalone.sh -d /tmp/vcontainer -y
    source /tmp/vcontainer/init-env.sh

    vdkr images
    vdkr vimport /path/to/container-base-latest-oci/ test:latest
    vdkr vmemres start
    vdkr images
    vdkr vmemres stop
    vdkr clean


See Also
========

- `classes/container-cross-install.bbclass` - Main bundling class
- `classes/container-bundle.bbclass` - Package-based bundling
- `recipes-containers/vcontainer/README.md` - vdkr/vpdmn detailed documentation
- `tests/README.md` - Test documentation
