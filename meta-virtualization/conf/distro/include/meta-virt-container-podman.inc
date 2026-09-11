include meta-virt-container.inc

VIRTUAL-RUNTIME_container_engine ?= "podman"
VIRTUAL-RUNTIME_container_runtime ?= "crun"
# netavark is the only supported network backend since podman 6.0
# (containers/common removed CNI support entirely)
VIRTUAL-RUNTIME_container_networking ?= "netavark"
VIRTUAL-RUNTIME_container_dns ?= "aardvark-dns"
VIRTUAL-RUNTIME_container_orchestration ?= ""

## Kubernetes terminology "components"
VIRTUAL-RUNTIME_cri ?= "virtual-containerd"
VIRTUAL-RUNTIME_cni ?= "cni"
