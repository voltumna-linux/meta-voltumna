# Release notes

This is the release notes document for the AMD BSP. This document contains
information about the Yocto layers' git repos, their branches and commit
hashes, software versions, and known/fixed issues/limitations.

## Bitbake layers
| Layer             | Git Repo                                     | Branch    | Commit Hash/Tag                          |
|:------------------|:---------------------------------------------|:----------|:-----------------------------------------|
| poky              | git://git.yoctoproject.org/poky              | kirkstone | tags/yocto-4.0.5                         |
| meta-openembedded | git://git.openembedded.org/meta-openembedded | kirkstone | 50d4a8d2a983a68383ef1ffec2c8e21adf0c1a79 |
| meta-dpdk         | git://git.yoctoproject.org/meta-dpdk         | kirkstone | 0e62d02f2755fbbf7dfa6e243381377c0a1cd97c |
| meta-amd          | git://git.yoctoproject.org/meta-amd          | kirkstone | tags/kirkstone-e3000-ga-202301           |

## Software versions
| Software        | Version  |
|:----------------|:---------|
| Yocto Poky base | 4.0.5    |
| grub            | 2.06     |
| linux-yocto     | 5.15.68  |
| linux-yocto-rt  | 5.15.68  |
| gcc             | 11.3.0   |
| util-linux      | 2.37.4   |
| lttng           | 2.13     |
| babeltrace      | 1.5.8    |
| connman         | 1.41     |
| gdb             | 11.2     |
| dpdk            | 21.11.2  |
| strongswan      | 5.9.6    |

## Fixed issues

## Known issues

* v3000: PORT0 does not work in finsar FCLF8520P2BTL
