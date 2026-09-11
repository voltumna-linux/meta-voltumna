include meta-virt-container.inc

# LXC is a Linux Containers user-space toolset for system containers.
# Unlike OCI engines (docker, podman, containerd) it doesn't use the
# OCI runtime/networking model — lxc-net.service brings up its own
# lxcbr0 bridge, and templates are scripts under /usr/share/lxc/templates
# rather than OCI bundles.
VIRTUAL-RUNTIME_container_engine ??= "lxc"
VIRTUAL-RUNTIME_container_runtime ??= ""
VIRTUAL-RUNTIME_container_networking ??= ""
VIRTUAL-RUNTIME_container_dns ??= ""
VIRTUAL-RUNTIME_container_orchestration ??= ""
