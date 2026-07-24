# k3s: Lightweight Kubernetes

Rancher's [k3s](https://k3s.io/), available under
[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0), provides
lightweight Kubernetes suitable for small/edge devices.

## Build

Add to `local.conf`:

```bash
require conf/distro/include/meta-virt-host.conf
require conf/distro/include/container-host-k3s.conf
require conf/distro/include/meta-virt-dev.conf
MACHINE = "qemux86-64"
```

Build:

```bash
bitbake container-image-host
```

## Single-Node Quick Start

```bash
runqemu qemux86-64 container-image-host ext4 nographic kvm slirp qemuparams="-m 4096"
```

After boot, k3s server starts automatically:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes          # should show Ready
kubectl get pods -A        # system pods (coredns, metrics-server, etc.)
kubectl run test --image=busybox --restart=Never -- sleep 300
kubectl get pods           # test pod Running
```

## Multi-Node Cluster (QEMU Socket Networking)

Uses QEMU socket networking to connect two VMs on a shared L2 segment.
No root, no TAP, no bridge required.

**Terminal 1 — Server:**

```bash
./scripts/run-k3s-multinode.sh server
```

After boot, get the join token:

```bash
k3s-get-token
```

**Terminal 2 — Agent:**

```bash
./scripts/run-k3s-multinode.sh agent --token <TOKEN>
```

**Verify on server (~30s after agent boot):**

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes          # 2 nodes Ready
```

### How It Works

- Both VMs boot the same `container-image-host` image (k3s profile)
- The agent VM gets `k3s.role=agent` on the kernel cmdline
- `k3s-role-setup.service` reads the cmdline and:
  - Configures the cluster network interface (eth1) via systemd-networkd
  - Masks the k3s server service
  - Starts the k3s agent with the provided token
- The `10-k3s-cluster.network` file (installed via `virt_networking` bbclass)
  claims eth1 and disables DHCP, preventing networkd from interfering

### Kernel Cmdline Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `k3s.role=` | `server` or `agent` | `server` |
| `k3s.server=` | Server IP (agent mode) | — |
| `k3s.token=` | Join token (agent mode) | — |
| `k3s.node-name=` | Override node name | hostname |
| `k3s.node-ip=` | Static IP on cluster interface | — |
| `k3s.iface=` | Cluster network interface | `eth1` |

## CNI

K3s uses flannel as the default CNI with VXLAN backend. The flannel
CNI config is installed to `/etc/cni/net.d/cni-flannel.conflist`.
CNI plugin binaries are in `/opt/cni/bin/`.

See <https://docs.k3s.io/networking> for further k3s networking details.

## Traefik Ingress

Traefik is enabled by default via PACKAGECONFIG. To disable:

```bash
PACKAGECONFIG:remove:pn-k3s = "traefik"
```

## Packages

| Package | Contents |
|---------|----------|
| `k3s` | Base binary, kubectl symlink, helpers |
| `k3s-server` | k3s.service (systemd, auto-enabled) |
| `k3s-agent` | k3s-agent.service (systemd, disabled by default) |
| `k3s-cni` | Flannel CNI config |
| `k3s-net-conf` | Cluster interface networkd config |

## Useful Commands

```bash
# Get join token (server only)
k3s-get-token

# Check k3s status
systemctl status k3s
journalctl -u k3s --no-pager -n 30

# Kubernetes commands
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
kubectl get pods -A
kubectl run test --image=busybox --restart=Never -- sleep 300
kubectl delete pod test
```

## Automated Testing

```bash
# Single-node tests
pytest tests/test_k3s_runtime.py -v -k "not multinode" --machine qemux86-64

# Multi-node tests
pytest tests/test_k3s_runtime.py -v -k "multinode" --machine qemux86-64
```

## Notes

**Memory:** K3s needs at least 2GB. Boot with `-m 4096` for comfortable
operation with system pods + workloads.

**Disk:** The default ext4 rootfs has enough space for k3s. If using
core-image-minimal, add `IMAGE_ROOTFS_EXTRA_SPACE = "2097152"`.

**KVM:** Strongly recommended. Without KVM, k3s startup takes
significantly longer under TCG emulation.

**k3s kubectl:** The embedded `k3s kubectl` subcommand is not available
in this build. Use `kubectl` directly with `KUBECONFIG=/etc/rancher/k3s/k3s.yaml`.
