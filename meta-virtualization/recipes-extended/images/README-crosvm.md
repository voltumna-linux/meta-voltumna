# crosvm-image-minimal: build and test

Steps to test/validate crosvm are given below.
A reference image `crosvm-image-minimal` is provided
for this purpose.

## local.conf example

```conf
# virtualization
MACHINE ??= "qemux86-64"
DISTRO ??= "nodistro"
BBMULTICONFIG ?= ""

DISTRO_FEATURES += " kvm virtualization"
IMAGE_FEATURES += " empty-root-password allow-empty-password allow-root-login"
IMAGE_FSTYPES = "ext4"
IMAGE_FSTYPES:remove = "ext4.zst"
```

## Build

```bash
bitbake crosvm-image-minimal
```

## Boot in QEMU

When the target `MACHINE` is `qemux86-64`, the host running QEMU must support:
- nested virtualization
- Intel VT-x or AMD SVM
- exposed `/dev/kvm`

Run from `tmp/deploy/images/qemux86-64/` (or adjust paths):

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -machine q35 \
  -cpu host \
  -smp 4 \
  -m 4096 \
  -kernel bzImage \
  -drive file=crosvm-image-minimal-qemux86-64.rootfs.ext4,format=raw,if=virtio \
  -append "root=/dev/vda rw console=ttyS0 earlyprintk=serial nokaslr" \
  -nographic
```

## Run crosvm inside the guest

The image bundles:

- `/var/lib/crosvm/images/guest-kernel`
- `/var/lib/crosvm/images/guest.ext4`

```bash
crosvm --log-level "debug,disk=off" run \
  --disable-sandbox  /var/lib/crosvm/images/guest-kernel \
  --block /var/lib/crosvm/images/guest.ext4,root \
  -p "root=/dev/vda rw console=ttyS0 earlyprintk=serial nokaslr"
```

## Quick sanity checks

```bash
test -e /dev/kvm && echo "/dev/kvm present"
ls -l /var/lib/crosvm/images/
```
