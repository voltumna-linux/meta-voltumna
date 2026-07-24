include meta-virt-container.inc

# Incus is a system container and VM manager built on LXC.
# It does not use the OCI container engine/runtime/networking model.
VIRTUAL-RUNTIME_container_engine ??= "incus"
VIRTUAL-RUNTIME_container_runtime ??= ""
VIRTUAL-RUNTIME_container_networking ??= ""
VIRTUAL-RUNTIME_container_dns ??= ""
VIRTUAL-RUNTIME_container_orchestration ??= ""
