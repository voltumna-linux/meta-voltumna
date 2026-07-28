# meta-clang-revival

This Yocto layer contains older CLANG versions revived from [meta-clang](https://github.com/kraj/meta-clang).

[meta-clang](https://github.com/kraj/meta-clang) only maintains a single version of CLANG, which is always the latest version matching the LLVM version in [openembedded-core](https://github.com/openembedded/openembedded-core.git).

The problem with only keeping a single LLVM or CLANG version is that crucial projects are slow to update their LLVM version support:

* [IGC of Intel Compute Runtime](https://github.com/intel/intel-graphics-compiler) supports up to LLVM 15, with LLVM 14 being production quality for the legacy versions.
* The [llvmlite](https://pypi.org/project/llvmlite/) Python module in version 0.43 supports LLVM 14 or 15

# Usage

[meta-clang](https://github.com/kraj/meta-clang) optionally suggests setting the default compiler to CLANG:

```shell
TOOLCHAIN ?= "clang"
```

**When using the `meta-clang-revival` layer, don't do this as it wasn't tested yet.**

Besides this, this layer allows building the Intel Compute Runtime in two variants:

* `intel-compute-runtime-legacy1` ported from an older version of `intel-compute-runtime` found in [meta-intel](https://git.yoctoproject.org/git/meta-intel) that supports Intel Gen11 and older GPU plaforms. This variant is built against **LLVM 14**.
* `intel-compute-runtime` (a.k.a. the current version from `meta-intel`) that support Intel Gen12 and newer GPU platforms. This variant is built against **LLVM 15**.

[meta-python-ai](https://github.com/zboszor/meta-python-ai) also relies on this layer for building the `python3-llvmlite` package.

(C) Zoltán Böszörményi <zboszor@gmail.com>
