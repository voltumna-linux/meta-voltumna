# meta-clang-revival

This Yocto layer contains older CLANG versions revived from [meta-clang](https://github.com/kraj/meta-clang).

[meta-clang](https://github.com/kraj/meta-clang) only maintains a single version of CLANG, which is always the latest version matching the LLVM version in [openembedded-core](https://github.com/openembedded/openembedded-core.git).

The problem with only keeping a single LLVM or CLANG version is that crucial projects are slow to update their LLVM version support:

* [IGC of Intel Compute Runtime](https://github.com/intel/intel-graphics-compiler) supports up to LLVM 15
* The [llvmlite](https://pypi.org/project/llvmlite/) Python module in version 0.43 supports LLVM 14 or 15

# Usage

[meta-clang](https://github.com/kraj/meta-clang) optionally suggests setting the default compiler to CLANG:

```shell
TOOLCHAIN ?= "clang"
```

**When using the `meta-clang-revival` layer, don't do this.**

Besides this, this layer automatically allows building the Intel Compute Runtime with CLANG 15 in [meta-intel](https://git.yoctoproject.org/git/meta-intel).

[meta-python-ai](https://github.com/zboszor/meta-python-ai) also relies on this layer for building the `python3-llvmlite` package.

(C) Zoltán Böszörményi <zboszor@gmail.com>
