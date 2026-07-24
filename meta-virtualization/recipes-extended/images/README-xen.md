This README contains information on the xen reference images
and testing / usability information

Images
------

xen-image-minimal:

This is the reference xen host image. It currently requires systemd
and xen as DISTRO_FEATURES.

All required dependencies are included for typical execution (and
debug) of guests.

xen-guest-image-minimal:

This is the reference guest / domU image. Note that it boots the
same kernel as the xen host image (unless multiconfig is used
to differentiate).

It creates tarballs, ext4 and qcow images for testing purposes.

Bundling
--------

There are two ways to bundle Xen guests into a Dom0 host image:

| Use Case | `BUNDLED_XEN_GUESTS` | Bundle Recipe |
|---|---|---|
| Simple: guests in one host image | recommended | overkill |
| Reuse guests across multiple host images | repetitive | recommended |
| Package versioning and dependencies | not supported | supported |
| Distribute pre-built guest sets | not supported | supported |

### Variable-driven (BUNDLED_XEN_GUESTS)

Guests can be bundled into the host image automatically using
`xen-guest-cross-install.bbclass` (inherited by xen-image-minimal).

Set `BUNDLED_XEN_GUESTS` in local.conf or the image recipe:

  BUNDLED_XEN_GUESTS = "xen-guest-image-minimal:autostart"

Each entry is a recipe name with optional tags:

  recipe-name[:autostart][:external]

  - recipe-name: Yocto image recipe that produces the guest rootfs
  - autostart: Creates symlink in /etc/xen/auto/ for xendomains
  - external: Skip dependency generation (3rd-party guest)

Examples:

  # Single guest with autostart (default recommendation)
  BUNDLED_XEN_GUESTS = "xen-guest-image-minimal:autostart"

  # Guest without autostart
  BUNDLED_XEN_GUESTS = "xen-guest-image-minimal"

  # External/3rd-party guest (no build dependency)
  BUNDLED_XEN_GUESTS = "my-vendor-guest:external"

Per-guest configuration via varflags:

  XEN_GUEST_MEMORY[xen-guest-image-minimal] = "1024"
  XEN_GUEST_VCPUS[xen-guest-image-minimal] = "2"
  XEN_GUEST_VIF[xen-guest-image-minimal] = "bridge=xenbr0"
  XEN_GUEST_EXTRA[xen-guest-image-minimal] = "root=/dev/xvda ro console=hvc0 ip=dhcp"

Custom config file (replaces auto-generation):

  SRC_URI += "file://my-custom-guest.cfg"
  BUNDLED_XEN_GUESTS = "xen-guest-image-minimal:autostart"
  XEN_GUEST_CONFIG_FILE[xen-guest-image-minimal] = "${UNPACKDIR}/my-custom-guest.cfg"

Explicit rootfs/kernel for external guests:

  XEN_GUEST_ROOTFS[my-vendor-guest] = "vendor-rootfs.ext4"
  XEN_GUEST_KERNEL[my-vendor-guest] = "vendor-kernel"

### Package-based (xen-guest-bundle.bbclass)

For reusable guest sets, create a bundle recipe that inherits
`xen-guest-bundle`:

  # recipes-extended/xen-guest-bundles/my-guests_1.0.bb
  inherit xen-guest-bundle

  XEN_GUEST_BUNDLES = "xen-guest-image-minimal:autostart"
  XEN_GUEST_MEMORY[xen-guest-image-minimal] = "1024"

Then install the bundle in the host image:

  IMAGE_INSTALL:append:pn-xen-image-minimal = " my-guests"

The bundle package includes rootfs, kernel, and config files. At
image time, `merge_installed_xen_bundles()` deploys them to the
same target locations as the variable-driven path.

Custom config files work the same way via SRC_URI + varflag:

  SRC_URI += "file://my-custom-guest.cfg"
  XEN_GUEST_CONFIG_FILE[xen-guest-image-minimal] = "${UNPACKDIR}/my-custom-guest.cfg"

See `example-xen-guest-bundle_1.0.bb` for a complete example.

### 3rd-party guest import

The import system converts fetched source formats (tarballs, qcow2 images,
etc.) into Xen-ready disk images at build time. This is for guests that
are not built by Yocto (e.g., Alpine minirootfs, Debian cloud images).

Per-guest varflags control the import:

  XEN_GUEST_SOURCE_TYPE[guest] = "rootfs_dir"   # import handler type
  XEN_GUEST_SOURCE_FILE[guest] = "alpine-rootfs" # file/dir in UNPACKDIR
  XEN_GUEST_IMAGE_SIZE[guest] = "128"            # target image size in MB

Built-in import types:

| Type | Input | Output | Tool |
|---|---|---|---|
| `rootfs_dir` | Extracted rootfs directory | ext4 image | `mkfs.ext4 -F -d` |
| `qcow2` | QCOW2 disk image | raw image | `qemu-img convert` |
| `ext4` | ext4 image file | ext4 (copy) | `cp` |
| `raw` | raw disk image | raw (copy) | `cp` |

Native tool dependencies are resolved automatically at parse time.

Kernel modes (per-guest via `XEN_GUEST_KERNEL` varflag):

  - (not set): Shared host kernel from DEPLOY_DIR_IMAGE
  - `"path"`: Custom kernel from UNPACKDIR or DEPLOY_DIR_IMAGE
  - `"none"`: HVM guest, no kernel (omits kernel= from config)

Alpine example (`alpine-xen-guest-bundle_3.23.bb`):

  inherit xen-guest-bundle

  SRC_URI = "https://...alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz;subdir=alpine-rootfs"

  XEN_GUEST_BUNDLES = "alpine:autostart:external"
  XEN_GUEST_SOURCE_TYPE[alpine] = "rootfs_dir"
  XEN_GUEST_SOURCE_FILE[alpine] = "alpine-rootfs"
  XEN_GUEST_IMAGE_SIZE[alpine] = "128"
  XEN_GUEST_MEMORY[alpine] = "256"
  XEN_GUEST_EXTRA[alpine] = "root=/dev/xvda ro console=hvc0"

Adding custom import types: define a shell function
`xen_guest_import_<type>(source_path, output_path, size_mb)` in a
bbclass, recipe, or bbappend and set the corresponding
`XEN_GUEST_IMPORT_DEPENDS_<type>` variable for native tool dependencies.

Target layout
-------------

kernel and rootfs are copied to the target in /var/lib/xen/images/

configuration files are copied to: /etc/xen

autostart symlinks are created in: /etc/xen/auto/

Guests can be launched after boot with: xl create -c /etc/xen/<guest>.cfg

Build and boot
--------------

### qemuarm64

Using a reference qemuarm64 MACHINE, the following are the commands
to build and boot a guest.

local.conf contains:

   BUNDLED_XEN_GUESTS = "xen-guest-image-minimal:autostart"

 % bitbake xen-guest-image-minimal
 % bitbake xen-image-minimal

 % runqemu qemuarm64 nographic slirp qemuparams="-m 4096"

Poky (Yocto Project Reference Distro) 5.1 qemuarm64 hvc0

qemuarm64 login: root

root@qemuarm64:~# ls /etc/xen/
auto
cpupool
scripts
xen-guest-image-minimal.cfg
xl.conf
root@qemuarm64:~# ls /var/lib/xen/images/
Image--6.10.11+git0+4bf82718cf_6c956b2ea6-r0-qemuarm64-20241018190311.bin
xen-guest-image-minimal-qemuarm64-20241111222814.ext4

 root@qemuarm64:~# xl create -c /etc/xen/xen-guest-image-minimal.cfg

qemuarm64 login: root

root@qemuarm64:~# uname -a
Linux qemuarm64 6.10.11-yocto-standard #1 SMP PREEMPT Fri Sep 20 22:32:26 UTC 2024 aarch64 GNU/Linux

From the host:

root@qemuarm64:~# xl list
Name                                        ID   Mem VCPUs      State   Time(s)
Domain-0                                     0   192     4     r-----     696.2
xen-guest-image-minimal                      1   512     1     -b----     153.0
root@qemuarm64:~# xl destroy xen-guest-image-minimal

### qemux86-64

The xen-image-minimal recipe includes x86-64 specific configuration:

  - QB_CPU_KVM uses -cpu host to avoid AVX stripping by Xen's CPUID
    filtering (required for x86-64-v3 tune)
  - QB_MEM_VALUE = "1024" for 1GB Dom0 memory
  - dom0_mem=512M reserves memory for DomU guests

 % MACHINE=qemux86-64 bitbake xen-guest-image-minimal
 % MACHINE=qemux86-64 bitbake xen-image-minimal

 % runqemu qemux86-64 nographic slirp kvm qemuparams="-m 4096"

qemux86-64 login: root

root@qemux86-64:~# xl list
Name                                        ID   Mem VCPUs      State   Time(s)
Domain-0                                     0   512     4     r-----      12.3
alpine                                       1   256     1     -b----       0.8
xen-guest-image-minimal                      2   256     1     -b----       3.1

vxn standalone test:

root@qemux86-64:~# vxn run --rm alpine echo hello
hello

containerd test:

root@qemux86-64:~# ctr image pull docker.io/library/alpine:latest
root@qemux86-64:~# vctr run --rm docker.io/library/alpine:latest test1 echo hello
hello

vxn and containerd integration
------------------------------

vxn runs OCI containers as Xen DomU guests. The VM IS the container —
no Docker daemon runs inside the guest. The guest boots a minimal Linux,
mounts the container's filesystem, and directly executes the entrypoint.

There are multiple execution paths, all coexisting on the same Dom0:

| Path | CLI | How it works |
|------|-----|-------------|
| containerd | `vctr run`, `ctr run` | containerd → shim → vxn-oci-runtime → xl create |
| vxn standalone | `vxn run` | OCI pull on host → xl create → guest exec |
| vdkr/vpdmn | `vdkr run`, `vpdmn run` | Docker/Podman-like CLI, no daemon, auto-detects Xen |
| Native Docker | `docker run --network=none` | dockerd → containerd → vxn-oci-runtime |
| Native Podman | `podman run --network=none` | conmon → vxn-oci-runtime |

To enable vxn and containerd on a Dom0 image, add to local.conf:

  DISTRO_FEATURES:append = " virtualization vcontainer vxn"
  IMAGE_INSTALL:append:pn-xen-image-minimal = " vxn"
  BBMULTICONFIG = "vruntime-aarch64 vruntime-x86-64"

See recipes-core/vxn/README.md for full package and build details.

Memory requirements
-------------------

The recipe sets QB_MEM_VALUE = "1024" (1 GB total QEMU memory). This is
sufficient for Dom0 + one bundled guest, but not enough for vxn/vctr
which need to create additional Xen domains at runtime.

For vxn/containerd testing, pass extra memory via qemuparams:

  % runqemu qemux86-64 nographic slirp kvm qemuparams="-m 4096"

Memory budget at 4 GB total:

  | Component | Memory |
  |-----------|--------|
  | Domain-0  | 512 MB (dom0_mem=512M) |
  | Alpine guest (bundled) | 256 MB |
  | vxn/vctr guest | 256 MB |
  | Free for additional guests | ~3 GB |

Runtime tests
-------------

The pytest suite in tests/test_xen_runtime.py boots xen-image-minimal
via runqemu and verifies the Xen environment end-to-end:

  | Test Class | What It Checks |
  |------------|---------------|
  | TestXenDom0Boot | xl list shows Domain-0, dmesg has Xen messages, memory cap |
  | TestXenGuestBundleRuntime | Bundled guests visible in xl list, xendomains service |
  | TestXenVxnStandalone | vxn binary present, vxn run --rm alpine echo hello |
  | TestXenContainerd | containerd active, ctr pull + vctr run |

Build prerequisites (cumulative — each tier adds to the previous):

  # Tier 1: Dom0 boot tests
  DISTRO_FEATURES:append = " xen systemd"
  bitbake xen-image-minimal

  # Tier 2: Guest bundling tests
  IMAGE_INSTALL:append:pn-xen-image-minimal = " alpine-xen-guest-bundle"

  # Tier 3: vxn/containerd tests
  DISTRO_FEATURES:append = " virtualization vcontainer vxn"
  IMAGE_INSTALL:append:pn-xen-image-minimal = " vxn"
  BBMULTICONFIG = "vruntime-aarch64 vruntime-x86-64"

Running the tests:

  % cd meta-virtualization
  % pip install pytest pexpect

  # All tests (requires KVM and built image)
  % pytest tests/test_xen_runtime.py -v --machine qemux86-64

  # Core hypervisor tests only (skip network-dependent vxn/containerd)
  % pytest tests/test_xen_runtime.py -v -m "boot and not network"

  # With custom timeout or no KVM
  % pytest tests/test_xen_runtime.py -v --boot-timeout 180 --no-kvm

Tests detect available features inside Dom0 and skip gracefully when
optional components (vxn, containerd, bundled guests) are not installed.
The vxn/vctr tests also check Xen free memory and skip if insufficient
for creating new domains.
