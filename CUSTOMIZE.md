# 4. Customizing images with AMD Features

AMD supports various features and software components that can be
enabled by setting the corresponding configuration variable to a
valid value in the `local.conf`.

Following is a list of components that can be enabled if you want
them to be installed/available on your image, or can be configured:

* **ON-TARGET DEVELOPMENT - SDK for on-target development**

> gcc, make, autotools, autoconf, build-essential etc.

* **ON-TARGET DEBUGGING - tools for on-target debugging**

> gdb, gdbserver, strace, mtrace

* **ON-TARGET PROFILING - tools for on-target profiling**

> lttng, babeltrace, systemtap, powertop, valgrind

* **RT KERNEL - Realtime Kernel support**

> Linux kernel with PREEMPT_RT patch

---
##### Note

Please set the required configuration variables as shown below in the
`local.conf` **before building an image or generating an SDK** (that
can be used to develop apps for these components (if applicable)).

Otherwise they will not be configured, and will not be available on the
target.

---

#### Supported software features

| Software feature      | Configuration variable            | Configuration values        | Default value | Supported machines |
|:----------------------|:----------------------------------|:----------------------------|:--------------|:-------------------|
| ON-TARGET DEVELOPMENT | EXTRA_IMAGE_FEATURES:append       | tools-sdk                   |               | all                |
| ON-TARGET DEBUGGING   | EXTRA_IMAGE_FEATURES:append       | tools-debug                 |               | all                |
| ON-TARGET PROFILING   | EXTRA_IMAGE_FEATURES:append       | tools-profile               |               | all                |
| RT KERNEL             | PREFERRED_PROVIDER_virtual/kernel | linux-yocto, linux-yocto-rt | linux-yocto   | all                |

#### Example configuration in local.conf
```sh
EXTRA_IMAGE_FEATURES:append = " tools-sdk"
EXTRA_IMAGE_FEATURES:append = " tools-debug"
EXTRA_IMAGE_FEATURES:append = " tools-profile"

# Please run 'bitbake -c clean virtual/kernel' everytime before
# configuring the PREFERRED_PROVIDER_virtual/kernel variable
PREFERRED_PROVIDER_virtual/kernel = "linux-yocto-rt"
```

If you use the iso image, you can choose to `boot` from iso directly, or
to `install` the system to existing hard drive.

By default, the user interactive console is the serial port.

To install from vga console, edit the platform config file of you machine
`meta-amd-bsp/conf/machine/include/<platform>.inc`
and set tty0 as the last console option of the `APPEND` variable.

Example:
```
Set `APPEND += "console=tty0 console=ttyS0,115200n8"` to install from serial console.
Set `APPEND += "console=ttyS0,115200n8 console=tty0"` to install from vga console.
```

---
#### What's next

Continue to "Section 2 - Setting up and starting a build"
([BUILD.md](BUILD.md#23-start-the-build)) and restart the image build
as `bitbake <image-name>`, and deploy the new image to see the
changes take effect.
