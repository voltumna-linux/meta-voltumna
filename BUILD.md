# 2. Setting up and starting a build

After setting up the build system ([SETUP.md](SETUP.md)), we can build
images or recipes for a target machine (or BSP).
Running the commands in the instructions below will setup a build for
a selected AMD machine, and will start a build:

### 2.1. Select a target machine

Set the environment variable `MACHINE` to one of the supported AMD machines
(i.e `milan`, `rome`, `v3000`, `genoa` or `e3000`) that you want to build an
image for (change the `<machine-name>` in the following example accordingly):

```sh
MACHINE="<machine-name>"
```

### 2.2. Setup the build environment for selected machine

Source the *oe-init-build-env* script:
```sh
source ./oe-init-build-env build-${MACHINE}-${YOCTO_BRANCH}
```

Set the `MACHINE` and `DISTRO` bitbake environment variables in the
`conf/local.conf` (or `auto.conf`):
```sh
tee conf/auto.conf <<EOF
DL_DIR ?= "\${TOPDIR}/../downloads"
SSTATE_DIR ?= "\${TOPDIR}/../sstate-cache"

MACHINE = "${MACHINE}"
DISTRO = "poky-amd"
EOF
```

Add the required layers to the build configuration:
```sh
bitbake-layers add-layer ../meta-openembedded/meta-oe
bitbake-layers add-layer ../meta-openembedded/meta-python
bitbake-layers add-layer ../meta-openembedded/meta-networking
bitbake-layers add-layer ../meta-dpdk
bitbake-layers add-layer ../meta-amd/meta-amd-distro
bitbake-layers add-layer ../meta-amd/meta-amd-bsp
```

### 2.3. Start the build

Build one of the supported image recipes:
```sh
bitbake <image-name> -k
```

###### where `<image-name>` is to be replaced with one of the supported images for the selected AMD machine. See *supported features* section for a list all supported images for your machine.
###### (e.g. `core-image-sato` or `core-image-base`)

---
#### What's next

Continue to "Section 3 - Deploying an image to the target"
([DEPLOY.md](DEPLOY.md)) for instructions on booting the target with
the newly built image.

You can also customize the image ([CUSTOMIZE.md](CUSTOMIZE.md)) by
enabling/disabling certain configurable features in the `local.conf`.
Make sure to re-build the image before deploying the customized build.
