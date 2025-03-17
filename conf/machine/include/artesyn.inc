KERNEL_PROVIDER ?= "linux-artesyn"
PREFERRED_PROVIDER_virtual/kernel ?= "${KERNEL_PROVIDER}"

MACHINE_ESSENTIAL_EXTRA_RDEPENDS:append = "kernel-modules kernel-devicetree"
