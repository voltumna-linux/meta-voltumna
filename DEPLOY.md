# 3. Deploying an image to the target

After building an image ([BUILD.md](BUILD.md)), we can deploy it to the
target machine using a USB Flash Drive or a CD/DVD. The built images can be
found in the `<build-dir>/tmp/deploy/images/<machine-name>` directory to
which we will refer to as the **"Image Deploy Directory"** in this doc.

---
##### Note
Change the `<machine-name>` and `<image-name>` placeholders in the
following instructions according to the selected machine and the image 
built in "Section 2 - Setting up and starting a build" ([BUILD.md](BUILD.md)).

---

Change directory to the Image Deploy Directory:
```sh
cd tmp/deploy/images/<machine-name>
```

This directory contains `.wic` and `.iso` images for USB and CD/DVD
respectively. Follow the instructions below to make a bootable
USB Flash Drive or a CD/DVD by writing/burning the image to it:

### 3.1a. Deploy using a USB Flash Drive

We can use **bmaptool** (from *bmap-tools* package) or **dd** to write
the `<image-name>-<machine-name>.wic` image located in the
Image Deploy Directory to a USB Flash Drive:

##### Using bmaptool *(recommended)*
```sh
sudo bmaptool copy <image-name>-<machine-name>.wic /dev/<dev-node>
```

##### Using dd
```sh
sudo dd if=<image-name>-<machine-name>.wic of=/dev/<dev-node> \
conv=fdatasync status=progress
```

###### where `<dev-node>` is to be replaced with the device node of the USB Flash Drive.
###### (e.g. `sda`, `sdb` or `sdc` etc.)

### 3.1b. Deploy using a CD/DVD

You may use any CD/DVD burning tool to burn the
`<image-name>-<machine-name>.iso` image located in the
Image Deploy Directory onto a writable CD/DVD.

### 3.2. Booting the target

Insert the bootable USB or CD/DVD (created in above steps) into the
target machine and power ON the machine.

---
##### Note

You may need to press `Esc` key right after pressing the power ON
button to enter the BIOS setup and set the boot device priority/order
to boot from the inserted USB or CD/DVD.

---

The grub boot menu should appear at this point where you will see
options to `boot` or `install` this image:

* Select the `boot` option to boot up the target machine.

* Select the `install` option to install the image onto the target
machine's hard drive. Follow the instructions there to complete the
installation process, and reboot the machine and boot from the
hard drive you selected during the installation process.

You will be presented with a console (serial or graphical) or a
graphical user interface depending on the image and the target machine.

---
#### What's next

You can also customize the image ([CUSTOMIZE.md](CUSTOMIZE.md)) by
enabling/disabling certain configurable features in the `local.conf`.
Make sure to re-build the image ([BUILD.md](BUILD.md)) before deploying
the customized build.
