# meta-amd

This is the location for AMD BSP and AMD DISTRO layers.

Please see [AMD BSPs](meta-amd-bsp/README.md) for information about the
supported BSPs and their dependencies, and see
[AMD DISTRO](meta-amd-distro/README.md) for information about the
distro features.

## Getting started

Follow these simple steps to get started with setting up the
build system and start building images and recipes for the supported
AMD BSPs, and to deploy the built images on the target:

### 1. Setup 
Please see [SETUP.md](SETUP.md) for instructions on how to setup the
build system and the environment for it.

### 2. Build

Please see [BUILD.md](BUILD.md) for instructions on how to setup and
start a build for any of the supported AMD BSPs.

### 3. Deploy

Please see [DEPLOY.md](DEPLOY.md) for instructions on how to write/burn
a built image onto a USB/CD/DVD and boot the target machine with it.

#### What's next

* Please see [CUSTOMIZE.md](CUSTOMIZE.md) for instructions on how to
customize the build and to enable/disable any of the supported features
and software components to be included into the build.

* Please see [FEATURES.md](FEATURES.md) for a list of currently
supported features against each BSP.

* Please see [DOCUMENTATION.md](DOCUMENTATION.md) for links to official
documentation of various supported features and a general guide of the
Yocto Project.

* Please see [RELEASE.md](RELEASE.md) for release notes.

## Troubleshoot

If you have problems with or questions about a particular BSP, please
contact the maintainer of the particular layer as listed in the
MAINTAINERS section below directly (cc:ing the Yocto mailing list
puts it in the archive and helps other people who might have the same
questions in the future), but please try to do the following first:

  - look in the Yocto Project Bugzilla
    (http://bugzilla.yoctoproject.org/) to see if a problem has
    already been reported

  - look through recent entries of the meta-amd
    (https://lists.yoctoproject.org/pipermail/meta-amd/) and Yocto
    (https://lists.yoctoproject.org/pipermail/yocto/) mailing list
    archives to see if other people have run into similar problems or
    had similar questions answered.

If you believe you have encountered a bug, you can open a new bug and
enter the details in the Yocto Project Bugzilla
(http://bugzilla.yoctoproject.org/).  If you're relatively certain
that it's a bug against the BSP itself, please use the 'Yocto Project
Components: BSPs | meta-amd' category for the bug; otherwise, please
submit the bug against the most likely category for the problem - if
you're wrong, it's not a big deal and the bug will be recategorized
upon triage.

## Contribute

Please submit any patches against meta-amd BSPs to the meta-amd
mailing list (meta-amd@lists.yoctoproject.org).  Also, if your patches are
available via a public git repository, please also include a URL to
the repo and branch containing your patches as that makes it easier
for maintainers to grab and test your patches.

There are patch submission scripts available that will, among other
things, automatically include the repo URL and branch as mentioned.
Please see the Yocto Project Development Manual sections entitled
'Using Scripts to Push a Change Upstream and Request a Pull' and
'Using Email to Submit a Patch' for details.

Regardless of how you submit a patch or patchset, the patches should
at minimum follow the suggestions outlined in the 'How to Submit a
Change' secion in the Yocto Project Development Manual.  Specifically,
they should:

  - Include a 'Signed-off-by:' line.  A commit can't legally be pulled
    in without this.

  - Provide a single-line, short summary of the change.  This short
    description should be prefixed by the BSP or recipe name, as
    appropriate, followed by a colon.  Capitalize the first character
    of the summary (following the colon).

  - For the body of the commit message, provide detailed information
    that describes what you changed, why you made the change, and the
    approach you used.

  - If the change addresses a specific bug or issue that is associated
    with a bug-tracking ID, include a reference to that ID in your
    detailed description in the following format: [YOCTO #<bug-id>].

  - Pay attention to line length - please don't allow any particular
    line in the commit message to stretch past 72 characters.

  - For any non-trivial patch, provide information about how you
    tested the patch, and for any non-trivial or non-obvious testing
    setup, provide details of that setup.

Doing a quick 'git log' in meta-amd will provide you with many
examples of good example commits if you have questions about any
aspect of the preferred format.

The meta-amd maintainers will do their best to review and/or pull in
a patch or patchset within 24 hours of the time it was posted.  For
larger and/or more involved patches and patchsets, the review process
may take longer.

## Maintainers

The per layer gatekeepers are the following.

- meta-amd-bsp: Rahul Kumar <rahul.kumar1@amd.com>
- meta-amd-distro: Rahul Kumar <rahul.kumar1@amd.com>
