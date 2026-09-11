# Yocto Builder Container

## Build

To build a multiarch `container-yocto-builder`, we need to add it to
`CONTAINER_IMAGES` in `container-image-multiarch.bb`. This also required
modifying `vcontainer-bbmask.inc` to allow `python3-pexpect` and its
`python3-ptyprocess` dependency in order to satisfy the dependencies in
`packagegroup-yocto-builder-extras`. This then exposes
`meta-oe/dynamic-layers/meta-python` so we needed to add that to the mask.

To build the container:

```bash
bitbake container-image-multiarch-container-yocto-builder
```

### Missing Dependencies

During run-time testing, a few things were missing when following a `bitbake-setup` workflow.

* `ca-certificates` is needed for git cloning from `https://`

* `bitbake` needed `locale-base-en-us`

* `wss://` for `hashserv` (with `core/yocto/sstate-mirror-cdn` fragment) needed `python3-websockets`

* `bitbake-config-build` needed `util-linux-flock` and `util-linux-getopt`

   ```bash
   ERROR: The following required tools (as specified by HOSTTOOLS) appear to be unavailable in PATH, please install them in order to proceed:
     flock getopt
   ```

* `os-release` is needed to prevent the following warning, but for our multiarch containers, distro is `vcontainer` so `vcontainer-1.0` is not in sanity tested distros:

   ```bash
   WARNING: Host distribution "unknown" has not been validated with this version of the build system; you may possibly experience unexpected failures. It is recommended that you use a tested distribution.
   ```

* We need `glibc-dev`, so following the existing pattern in `packagegroup-yocto-builder`:

   ```bash
   ${@bb.utils.contains('TCLIBC', 'glibc', 'glibc-dev', '', d)}
   ```

   ```bash
   ERROR:  OE-core's config sanity checker detected a potential misconfiguration.
       Either fix the cause of this error or at your own risk disable the checker (see sanity.conf).
       Following is the list of potential problems / advisories:

       An unexpected issue occurred during the C++ toolchain check: Command '['g++', '-x', 'c++', '-', '-o', '/dev/null', '-lstdc++']' returned non-zero exit status 1.An error occurred during checking the C++ toolchain for '--std=gnu++20' support. Please use a g++ compiler that supports C++20 (e.g. g++ version 10 onwards).
   ```

   ```bash
   $ g++ --version
   g++ (GCC) 16.1.0
   Copyright (C) 2026 Free Software Foundation, Inc.
   This is free software; see the source for copying conditions.  There is NO
   warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

   builder@c9a0678daa85:/workdir/bitbake-builds/poky-master/build$ g++ -x c++ -lstd++
   /usr/bin/x86_64-poky-linux-ld: cannot find Scrt1.o: No such file or directory
   /usr/bin/x86_64-poky-linux-ld: cannot find crti.o: No such file or directory
   /usr/bin/x86_64-poky-linux-ld: cannot find crtbeginS.o: No such file or directory
   /usr/bin/x86_64-poky-linux-ld: cannot find -lstd++: No such file or directory
   /usr/bin/x86_64-poky-linux-ld: cannot find -lm: No such file or directory
   /usr/bin/x86_64-poky-linux-ld: cannot find -lgcc_s: No such file or directory
   /usr/bin/x86_64-poky-linux-ld: cannot find -lgcc: No such file or directory
   /usr/bin/x86_64-poky-linux-ld: cannot find -latomic_asneeded: No such file or directory
   /usr/bin/x86_64-poky-linux-ld: cannot find -lc: No such file or directory
   /usr/bin/x86_64-poky-linux-ld: cannot find -lgcc_s: No such file or directory
   /usr/bin/x86_64-poky-linux-ld: cannot find -lgcc: No such file or directory
   /usr/bin/x86_64-poky-linux-ld: cannot find crtendS.o: No such file or directory
   /usr/bin/x86_64-poky-linux-ld: cannot find crtn.o: No such file or directory
   collect2: error: ld returned 1 exit status
   ```

* We need `libgcc-dev`:

   ```bash
   $ g++ -x c++ -lstdc++
   /usr/bin/x86_64-poky-linux-ld: cannot find crtbeginS.o: No such file or directory
   collect2: error: ld returned 1 exit status
   ```

   ```bash
   $ oe-pkgdata-util -p tmp-container-aarch64/pkgdata/qemuarm64/ list-pkg-files libgcc-dev
   libgcc-dev:
     /usr/lib/aarch64-poky-linux/16.1.0/crtbegin.o
     /usr/lib/aarch64-poky-linux/16.1.0/crtbeginS.o
     /usr/lib/aarch64-poky-linux/16.1.0/crtbeginT.o
     /usr/lib/aarch64-poky-linux/16.1.0/crtend.o
     /usr/lib/aarch64-poky-linux/16.1.0/crtendS.o
     /usr/lib/aarch64-poky-linux/16.1.0/crtfastmath.o
     /usr/lib/aarch64-poky-linux/16.1.0/libgcc.a
     /usr/lib/aarch64-poky-linux/16.1.0/libgcc_eh.a
     /usr/lib/aarch64-poky-linux/16.1.0/libgcov.a
     /usr/lib/libgcc_s.so
     /usr/lib/libgcc_s_asneeded.so
   ```

* We need `libatomic-dev`:

   ```bash
   $ g++ -x c++ -lstdc++
   /usr/bin/x86_64-poky-linux-ld: cannot find -latomic_asneeded: No such file or directory
   collect2: error: ld returned 1 exit status
   ```

   ```bash
   $ oe-pkgdata-util -p tmp-container-aarch64/pkgdata/qemuarm64/ list-pkg-files libatomic-dev
   libatomic-dev:
     /usr/lib/libatomic.so
     /usr/lib/libatomic_asneeded.so
   ```

* We need `libgomp`:

   ```bash
   ERROR: base-files-3.0.14-r0 do_package: Fatal errors occurred in subprocesses:
   Command '['/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/recipe-sysroot-native/usr/lib/rpm/rpmdeps', '--alldeps', '--define', '__font_provides %{nil}', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/etc/hosts', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/etc/mtab', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/etc/nsswitch.conf', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/etc/issue', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/etc/motd', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/etc/fstab', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/etc/host.conf', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/etc/issue.net', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/etc/hostname', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/etc/shells', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/etc/profile', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/etc/skel/.bashrc', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/etc/skel/.profile', '/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/packages-split/base-files/var/lock']' returned non-zero exit status 127.
   Subprocess output:/workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/recipe-sysroot-native/usr/lib/rpm/rpmdeps: error while loading shared libraries: libgomp.so.1: cannot open shared object file: No such file or directory

   ERROR: Logfile of failure stored in: /workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/temp/log.do_package.136007
   ERROR: Task (/workdir/bitbake-builds/poky-master/layers/openembedded-core/meta/recipes-core/base-files/base-files_3.0.14.bb:do_package) failed with exit code '1'
   NOTE: Tasks Summary: Attempted 4002 tasks of which 2754 didn't need to be rerun and 1 failed.

   Summary: 1 task failed:
     /workdir/bitbake-builds/poky-master/layers/openembedded-core/meta/recipes-core/base-files/base-files_3.0.14.bb:do_package
       log: /workdir/bitbake-builds/poky-master/build/tmp/work/qemux86_64-poky-linux/base-files/3.0.14/temp/log.do_package.136007
   Summary: There was 1 WARNING message.
   Summary: There was 1 ERROR message, returning a non-zero exit code.
   ```

   The same was seen when building `gcc-runtime`.

   According to Claude, this is yet another missing dependency in the container:

   ```text
   ● Root cause found. Your yocto-builder container's own rootfs is missing libgomp.so.1 system-wide — it's not a bitbake config/sstate
   problem, it's a gap in the container image itself.
   ```

## Push

To push to a container registry:

```bash
 bitbake skopeo-native -c addto_recipe_sysroot
 oe-run-native skopeo-native skopeo copy --all \
   --dest-authfile /home/user/.config/containers/auth.json \
   oci:tmp/deploy/images/qemux86-64/container-image-multiarch-container-yocto-builder-multiarch-oci/ \
   docker://my.registry.io/user/yocto-builder:latest
```

## Run

This container is different compared to the CROPS `poky-container`, so we need
a few more arguments on the command line.

```bash
docker pull my.registry.io/user/yocto-builder:latest
docker run --privileged -d \
  --name yocto_builder \
  --rm -e BUILDER_UID=$(id -u) -e BUILDER_GID=$(id -g) \
  -v /path/to/workspace-yocto-builder:/workdir \
  my.registry.io/user/yocto-builder:latest
```

To get to a shell:

```bash
docker exec -it -w /workdir -u builder yocto_builder bash
```

You may want a different prompt, more like `poky-container`:

```bash
PS1="\u@\h:\w\$ "
```

At this point, you should be able to follow the [Quick Build][quick-build] guide in the [Yocto Project Documentation][yocto-docs].

## Building `core-image-minimal`

1. Clone `bitbake` so we can run `bitbake-setup`:

   ```bash
   git clone https://git.openembedded.org/bitbake.git
   ```

2. Setup `poky-master` non-interactively:

   ```bash
   bitbake/bin/bitbake-setup init --non-interactive poky-master poky distro/poky machine/qemux86-64
   ```

3. Initialize the `poky-master` build environment:

   ```bash
   . bitbake-builds/poky-master/build/init-build-env
   ```

4. (Optional) Enable config fragments:

   ```bash
   bitbake-config-build enable-fragment core/yocto/root-login-with-empty-password
   bitbake-config-build enable-fragment core/yocto/sbom-cve-check
   bitbake-config-build enable-fragment core/yocto/sstate-mirror-cdn
   ```

   You can also pass multiple fragments:

   ```bash
   bitbake-config-build enable-fragment core/yocto/root-login-with-empty-password  core/yocto/sbom-cve-check core/yocto/sstate-mirror-cdn
   ```

5. Build `core-image-minimal`

   ```bash
   bitbake core-image-minimal
   ```

6. Run `core-image-minimal`

   ```bash
   runqemu nographic slirp snapshot
   ```

<!-- References -->

[quick-build]: <https://docs.yoctoproject.org/brief-yoctoprojectqs/index.html>  
[yocto-docs]: <https://docs.yoctoproject.org>
