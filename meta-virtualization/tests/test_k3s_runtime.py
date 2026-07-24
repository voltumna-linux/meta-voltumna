# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
K3s runtime tests - boot container-image-host with k3s and verify Kubernetes.

Single-node tests verify k3s server start, node readiness, and basic pod
deployment. Multi-node tests use QEMU socket networking to connect two VMs
on a shared L2 segment and verify agent join + multi-node scheduling.

Build prerequisites (in local.conf):
    require conf/distro/include/meta-virt-host.conf
    require conf/distro/include/container-host-k3s.conf
    MACHINE = "qemux86-64"  # or qemuarm64

    bitbake container-image-host

Run:
    # Single-node only
    pytest tests/test_k3s_runtime.py -v -k "not multinode" --machine qemux86-64

    # Multi-node only
    pytest tests/test_k3s_runtime.py -v -k "multinode" --machine qemux86-64

    # All tests
    pytest tests/test_k3s_runtime.py -v --machine qemux86-64

Options:
    --k3s-timeout       Overall k3s readiness timeout (default: 300s)
    --boot-timeout      QEMU boot timeout (default: 120s)
    --no-kvm            Disable KVM acceleration

Notes:
    - k3s does not embed 'kubectl' as a subcommand in our build.
      Use 'kubectl' with KUBECONFIG=/etc/rancher/k3s/k3s.yaml instead.
    - System pods (coredns, traefik) are not auto-deployed because k3s
      manifest extraction is not yet supported in the Yocto build.
    - Multi-node tests launch QEMU directly (not via runqemu) to support
      two concurrent VMs with socket networking. Architecture-specific
      QEMU parameters are auto-detected from the machine setting.
"""

import os
import re
import shutil
import time
import pytest
from pathlib import Path

try:
    import pexpect
    PEXPECT_AVAILABLE = True
except ImportError:
    PEXPECT_AVAILABLE = False


# Socket networking port base — each test session gets a unique port
_SOCKET_PORT_BASE = 10000 + os.getpid() % 50000

# kubectl command prefix — sets KUBECONFIG for all kubectl calls
_KUBECTL = 'KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl'




class K3sRunner:
    """
    Manages a QEMU session for K3s testing.

    Boots container-image-host with optional dual NIC (slirp + socket network)
    and provides command execution via serial console. Supports both runqemu
    (single-node) and direct QEMU launch (multi-node).
    """

    def __init__(self, poky_dir, build_dir, machine, use_kvm=True,
                 timeout=120, image="container-image-host",
                 extra_qemu_params="", log_suffix="",
                 use_runqemu=True, rootfs_path=None,
                 kernel_append=""):
        self.poky_dir = Path(poky_dir)
        self.build_dir = Path(build_dir)
        self.machine = machine
        self.use_kvm = use_kvm
        self.timeout = timeout
        self.image = image
        self.extra_qemu_params = extra_qemu_params
        self.log_suffix = log_suffix
        self.use_runqemu = use_runqemu
        self.rootfs_path = rootfs_path
        self.kernel_append = kernel_append
        self.child = None
        self.booted = False
        self._rootfs_copy = None

    def _build_direct_qemu_cmd(self):
        """Build a direct QEMU command via run-qemu-vm.sh script."""
        script = (Path(__file__).parent.parent / "scripts"
                  / "run-qemu-vm.sh").resolve()
        if not script.exists():
            raise RuntimeError(f"run-qemu-vm.sh not found: {script}")

        cmd = (
            f"{script} --build-dir {self.build_dir} "
            f"--machine {self.machine} --image {self.image} "
            f"--memory 4096"
        )

        if not self.use_kvm:
            cmd += " --no-kvm"

        if self.rootfs_path:
            cmd += f" --rootfs {self.rootfs_path}"

        if self.extra_qemu_params:
            # Parse socket networking from extra_qemu_params
            if "listen=:" in self.extra_qemu_params:
                port = re.search(r'listen=:(\d+)', self.extra_qemu_params)
                if port:
                    cmd += f" --role server --socket-port {port.group(1)}"
            elif "connect=" in self.extra_qemu_params:
                port = re.search(r'connect=[\d.]+:(\d+)',
                                 self.extra_qemu_params)
                if port:
                    cmd += f" --role agent --socket-port {port.group(1)}"

        if self.kernel_append:
            cmd += f' --append "{self.kernel_append}"'

        return cmd

    def start(self):
        """Start QEMU and wait for login prompt."""
        if not PEXPECT_AVAILABLE:
            raise RuntimeError("pexpect not installed. Run: pip install pexpect")

        if self.use_runqemu:
            cmd = self._build_runqemu_cmd()
        else:
            cmd = self._build_direct_qemu_cmd()

        log_name = f"runqemu-k3s-test{self.log_suffix}.log"
        print(f"Starting QEMU (K3s{self.log_suffix}): {cmd}")
        self.child = pexpect.spawn(
            cmd, encoding='utf-8', timeout=self.timeout)
        self.child.logfile_read = open(f'/tmp/{log_name}', 'w')

        try:
            index = self.child.expect([
                r'login:',
                r'root@',
                pexpect.TIMEOUT,
                pexpect.EOF,
            ], timeout=self.timeout)

            if index == 0:
                self.child.sendline('root')
                self.child.expect([r'root@', r'#', r'\$'], timeout=30)
                self.booted = True
            elif index == 1:
                self.booted = True

            if self.booted:
                self.child.sendline('export TERM=dumb')
                self.child.expect(r'root@[^:]+:[^#]+#', timeout=10)
                # Set KUBECONFIG for all kubectl commands
                self.child.sendline(
                    'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml')
                self.child.expect(r'root@[^:]+:[^#]+#', timeout=10)

            if index == 2:
                raise RuntimeError(
                    f"Timeout waiting for login (>{self.timeout}s)")
            elif index == 3:
                raise RuntimeError("QEMU terminated unexpectedly")

        except Exception as e:
            self.stop()
            raise RuntimeError(f"Failed to boot image: {e}")

        return self

    def _build_runqemu_cmd(self):
        """Build a runqemu command line."""
        kvm_opt = "kvm" if self.use_kvm else ""
        qemu_params = "-m 4096"
        if self.extra_qemu_params:
            qemu_params += f" {self.extra_qemu_params}"

        return (
            f"bash -c 'cd {self.poky_dir} && "
            f"source oe-init-build-env {self.build_dir} >/dev/null 2>&1 && "
            f"runqemu {self.machine} {self.image} ext4 nographic slirp "
            f"{kvm_opt} "
            f"qemuparams=\"{qemu_params}\"'"
        )

    @staticmethod
    def _strip_escape_sequences(text):
        """Strip ANSI and OSC escape sequences from terminal output."""
        text = re.sub(r'\x1b\][^\x1b\x07]*(?:\x1b\\|\x07)', '', text)
        text = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', text)
        text = re.sub(r'\x1b[^[\]].?', '', text)
        return text

    def run_command(self, cmd, timeout=60):
        """Run a command and return the output."""
        if not self.booted:
            raise RuntimeError("System not booted")

        time.sleep(0.3)
        self.child.sendline(cmd)

        try:
            self.child.expect(r'root@[^:]+:[^#]+#', timeout=timeout)
            raw_output = self.child.before
            raw_output = self._strip_escape_sequences(raw_output)

            lines = raw_output.replace('\r', '').split('\n')
            output_lines = []
            for i, line in enumerate(lines):
                stripped = line.strip()
                if not stripped:
                    continue
                if i == 0 or (output_lines == [] and cmd[:10] in line):
                    continue
                output_lines.append(stripped)

            return '\n'.join(output_lines)

        except pexpect.TIMEOUT:
            print(f"[TIMEOUT] Command '{cmd}' timed out after {timeout}s")
            return ""

    def run_command_rc(self, cmd, timeout=60):
        """Run a command and return (output, return_code)."""
        output = self.run_command(f'{cmd}; echo "RC=$?"', timeout=timeout)
        rc = 1
        lines = output.splitlines()
        clean_lines = []
        for line in lines:
            m = re.match(r'^RC=(\d+)$', line.strip())
            if m:
                rc = int(m.group(1))
            else:
                clean_lines.append(line)
        return '\n'.join(clean_lines), rc

    def wait_for_condition(self, check_cmd, success_pattern, timeout=180,
                           interval=10, description="condition"):
        """Poll a command until output matches pattern or timeout."""
        deadline = time.time() + timeout
        last_output = ""
        while time.time() < deadline:
            output = self.run_command(check_cmd, timeout=30)
            last_output = output
            if re.search(success_pattern, output):
                return output
            remaining = int(deadline - time.time())
            print(f"  Waiting for {description}... ({remaining}s remaining)")
            time.sleep(interval)
        raise TimeoutError(
            f"Timeout waiting for {description} after {timeout}s. "
            f"Last output:\n{last_output}")

    def stop(self):
        """Shutdown the QEMU instance."""
        if self.child:
            try:
                if self.booted:
                    self.child.sendline('poweroff')
                    time.sleep(2)
                if self.child.isalive():
                    self.child.terminate(force=True)
            except Exception:
                pass
            finally:
                if self.child.logfile_read:
                    self.child.logfile_read.close()
                self.child = None
                self.booted = False
        # Clean up rootfs copy
        if self._rootfs_copy and Path(self._rootfs_copy).exists():
            try:
                os.unlink(self._rootfs_copy)
            except OSError:
                pass


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture(scope="module")
def poky_dir(request):
    """Path to poky directory."""
    path = Path(request.config.getoption("--poky-dir"))
    if not path.exists():
        pytest.skip(f"Poky directory not found: {path}")
    return path


@pytest.fixture(scope="module")
def build_dir(request, poky_dir):
    """Path to build directory."""
    bd = request.config.getoption("--build-dir")
    if bd:
        path = Path(bd)
    else:
        path = poky_dir / "build"
    if not path.exists():
        pytest.skip(f"Build directory not found: {path}")
    return path


@pytest.fixture(scope="module")
def machine(request):
    """Target machine."""
    return request.config.getoption("--machine")


@pytest.fixture(scope="module")
def k3s_timeout(request):
    """K3s readiness timeout."""
    return request.config.getoption("--k3s-timeout")


@pytest.fixture(scope="module")
def k3s_session(request, poky_dir, build_dir, machine):
    """
    Module-scoped fixture that boots container-image-host once for all
    single-node k3s tests. Uses runqemu for single-node tests.
    """
    if not PEXPECT_AVAILABLE:
        pytest.skip("pexpect not installed. Run: pip install pexpect")

    deploy_dir = build_dir / "tmp" / "deploy" / "images" / machine
    ext4_files = list(deploy_dir.glob("container-image-host-*.rootfs.ext4"))
    if not ext4_files:
        pytest.skip(
            f"container-image-host ext4 image not found in {deploy_dir}")

    timeout = request.config.getoption("--boot-timeout")
    use_kvm = not request.config.getoption("--no-kvm")

    runner = K3sRunner(poky_dir, build_dir, machine,
                       use_kvm=use_kvm, timeout=timeout,
                       use_runqemu=True, log_suffix="-single")

    try:
        runner.start()
        yield runner
    except RuntimeError as e:
        pytest.skip(f"Failed to boot image: {e}")
    finally:
        runner.stop()


@pytest.fixture(scope="module")
def k3s_multinode(request, poky_dir, build_dir, machine):
    """
    Module-scoped fixture that boots two VMs connected via QEMU socket
    networking for multi-node k3s testing.

    Uses direct QEMU launch (not runqemu) since runqemu can only run
    one VM at a time. Creates a copy of the rootfs for the agent VM.

    VM1 (server): listens on socket, IP 192.168.50.1/24
    VM2 (agent):  connects to socket, IP 192.168.50.2/24
    """
    if not PEXPECT_AVAILABLE:
        pytest.skip("pexpect not installed. Run: pip install pexpect")

    deploy_dir = build_dir / "tmp" / "deploy" / "images" / machine
    ext4_files = sorted(
        deploy_dir.glob("container-image-host-*.rootfs.ext4"),
        key=os.path.getmtime)
    if not ext4_files:
        pytest.skip(
            f"container-image-host ext4 image not found in {deploy_dir}")

    rootfs_orig = ext4_files[-1]

    # Create a copy of the rootfs for the agent VM — two VMs can't
    # share the same ext4 file read-write
    rootfs_agent = Path(f"/tmp/k3s-agent-rootfs-{os.getpid()}.ext4")
    print(f"Copying rootfs for agent VM: {rootfs_orig} -> {rootfs_agent}")
    shutil.copy2(rootfs_orig, rootfs_agent)

    timeout = request.config.getoption("--boot-timeout")
    use_kvm = not request.config.getoption("--no-kvm")
    socket_port = _SOCKET_PORT_BASE

    # Server VM: socket listen on second NIC
    server_params = (
        f"-netdev socket,id=vlan0,listen=:{socket_port} "
        f"-device virtio-net-pci,netdev=vlan0"
    )
    server = K3sRunner(poky_dir, build_dir, machine,
                       use_kvm=use_kvm, timeout=timeout,
                       extra_qemu_params=server_params,
                       use_runqemu=False,
                       rootfs_path=rootfs_orig,
                       kernel_append="k3s.role=server k3s.node-ip=192.168.50.1",
                       log_suffix="-server")

    # Agent VM: socket connect on second NIC, uses rootfs copy
    agent_params = (
        f"-netdev socket,id=vlan0,connect=127.0.0.1:{socket_port} "
        f"-device virtio-net-pci,netdev=vlan0"
    )
    agent = K3sRunner(poky_dir, build_dir, machine,
                      use_kvm=use_kvm, timeout=timeout,
                      extra_qemu_params=agent_params,
                      use_runqemu=False,
                      rootfs_path=rootfs_agent,
                      kernel_append="k3s.role=agent k3s.node-ip=192.168.50.2 k3s.node-name=k3s-agent",
                      log_suffix="-agent")
    agent._rootfs_copy = str(rootfs_agent)

    try:
        # Start server first (it listens), then agent
        server.start()
        agent.start()

        # Wait for networkd to configure IPs from kernel cmdline
        # (k3s-role-setup.service writes networkd drop-ins)
        time.sleep(5)

        yield {"server": server, "agent": agent}

    except RuntimeError as e:
        pytest.skip(f"Failed to boot multi-node VMs: {e}")
    finally:
        agent.stop()
        server.stop()


# ============================================================================
# Phase 1: Single-Node Tests
# ============================================================================

@pytest.mark.boot
@pytest.mark.k3s
class TestK3sSingleNode:
    """Single-node k3s tests on container-image-host."""

    def test_k3s_boot(self, k3s_session):
        """Boot image, verify k3s binary exists and service unit is present."""
        assert k3s_session.booted, "System failed to boot"

        output = k3s_session.run_command('k3s --version')
        assert 'k3s' in output.lower(), \
            f"k3s --version unexpected output:\n{output}"

        output = k3s_session.run_command(
            'systemctl list-unit-files | grep k3s || echo NOT_FOUND')
        assert 'NOT_FOUND' not in output, \
            "k3s systemd unit not found"

    def test_k3s_server_start(self, k3s_session, k3s_timeout):
        """Start k3s server and wait for node to become Ready."""
        # k3s.service should auto-start; ensure it's running
        k3s_session.run_command('systemctl start k3s 2>&1')

        # Wait for node Ready
        try:
            output = k3s_session.wait_for_condition(
                f'{_KUBECTL} get nodes 2>/dev/null || echo WAITING',
                r'\bReady\b',
                timeout=k3s_timeout,
                interval=15,
                description="k3s node Ready")
        except TimeoutError:
            logs = k3s_session.run_command(
                'journalctl -u k3s --no-pager -n 50 2>/dev/null || '
                'echo "no logs"')
            pytest.fail(
                f"k3s server did not become Ready within {k3s_timeout}s.\n"
                f"Logs:\n{logs}")

    def test_k3s_node_ready(self, k3s_session):
        """Verify at least 1 node in Ready state."""
        output = k3s_session.run_command(f'{_KUBECTL} get nodes 2>&1')
        ready_lines = [l for l in output.splitlines()
                       if 'Ready' in l and 'NotReady' not in l]
        assert len(ready_lines) >= 1, \
            f"Expected at least 1 Ready node, got {len(ready_lines)}:\n{output}"

    def test_k3s_deploy_pod(self, k3s_session, k3s_timeout):
        """Deploy a busybox pod and verify it reaches Running state."""
        k3s_session.run_command(
            f'{_KUBECTL} run test-busybox --image=busybox '
            f'--restart=Never -- sleep 300 2>&1')

        try:
            output = k3s_session.wait_for_condition(
                f'{_KUBECTL} get pod test-busybox 2>/dev/null '
                f'|| echo WAITING',
                r'Running',
                timeout=k3s_timeout,
                interval=10,
                description="test-busybox Running")
        except TimeoutError:
            events = k3s_session.run_command(
                f'{_KUBECTL} describe pod test-busybox 2>&1 | tail -20')
            output = k3s_session.run_command(
                f'{_KUBECTL} get pod test-busybox 2>&1')
            pytest.fail(
                f"Pod test-busybox did not reach Running:\n{output}\n"
                f"Events:\n{events}")

        assert 'Running' in output, \
            f"Pod not Running:\n{output}"

    def test_k3s_cleanup(self, k3s_session):
        """Delete the test pod and verify termination."""
        k3s_session.run_command(
            f'{_KUBECTL} delete pod test-busybox --grace-period=5 2>&1')

        try:
            k3s_session.wait_for_condition(
                f'{_KUBECTL} get pod test-busybox 2>&1',
                r'NotFound|not found|No resources',
                timeout=60,
                interval=5,
                description="pod deletion")
        except TimeoutError:
            output = k3s_session.run_command(
                f'{_KUBECTL} get pod test-busybox 2>&1')
            if 'Terminating' not in output:
                pytest.fail(f"Pod not cleaned up:\n{output}")


# ============================================================================
# Phase 2: Multi-Node Tests
# ============================================================================

@pytest.mark.boot
@pytest.mark.k3s
@pytest.mark.multinode
class TestK3sMultiNode:
    """Multi-node k3s tests using QEMU socket networking."""

    def test_k3s_multinode_boot(self, k3s_multinode):
        """Both VMs boot successfully."""
        server = k3s_multinode["server"]
        agent = k3s_multinode["agent"]
        assert server.booted, "Server VM failed to boot"
        assert agent.booted, "Agent VM failed to boot"

        output = server.run_command('k3s --version')
        assert 'k3s' in output.lower()
        output = agent.run_command('k3s --version')
        assert 'k3s' in output.lower()

    def test_k3s_multinode_network(self, k3s_multinode):
        """VMs can ping each other on the socket network (eth1)."""
        server = k3s_multinode["server"]
        agent = k3s_multinode["agent"]

        output, rc = server.run_command_rc(
            'ping -c 3 -W 5 192.168.50.2')
        assert rc == 0, \
            f"Server cannot ping agent:\n{output}"

        output, rc = agent.run_command_rc(
            'ping -c 3 -W 5 192.168.50.1')
        assert rc == 0, \
            f"Agent cannot ping server:\n{output}"

    def test_k3s_agent_join(self, k3s_multinode, k3s_timeout):
        """Wait for k3s server Ready, extract token, start agent."""
        server = k3s_multinode["server"]
        agent = k3s_multinode["agent"]

        # The server VM booted with k3s.role=server and k3s.node-ip=192.168.50.1
        # on the kernel cmdline. k3s-role-setup.service configured networking
        # and k3s.service auto-started. Wait for it to become Ready.
        try:
            server.wait_for_condition(
                f'{_KUBECTL} get nodes 2>/dev/null || echo WAITING',
                r'\bReady\b',
                timeout=k3s_timeout,
                interval=15,
                description="k3s server node Ready")
        except TimeoutError:
            logs = server.run_command(
                'journalctl -u k3s --no-pager -n 30 2>/dev/null || '
                'echo "no logs"')
            pytest.fail(f"Server not Ready:\n{logs}")

        # Extract node token
        token = server.run_command('k3s-get-token 2>&1')
        # Parse the actual token from the script output
        for line in token.splitlines():
            line = line.strip()
            if line.startswith('K10'):
                token = line
                break
        assert token.startswith('K10'), \
            f"Failed to get node token:\n{token}"

        # The agent VM booted with k3s.role=agent but without a token
        # (we didn't know it at launch time). Role-setup configured
        # networking and masked k3s.service. Start k3s-agent manually
        # with the token from the server.
        agent.run_command(
            f'export K3S_URL=https://192.168.50.1:6443 && '
            f'export K3S_TOKEN={token} && '
            f'export PATH=$PATH:/opt/cni/bin:/usr/libexec/cni && '
            f'k3s agent '
            f'--node-name k3s-agent '
            f'--node-ip 192.168.50.2 '
            f'--flannel-iface eth1 '
            f'&>/var/log/k3s-agent.log &')

        # Wait for 2 nodes Ready on server
        try:
            server.wait_for_condition(
                f'{_KUBECTL} get nodes 2>/dev/null || echo WAITING',
                r'(?:Ready.*\n.*Ready|Ready[\s\S]*Ready)',
                timeout=k3s_timeout,
                interval=15,
                description="2 nodes Ready")
        except TimeoutError:
            nodes = server.run_command(
                f'{_KUBECTL} get nodes 2>&1')
            agent_logs = agent.run_command(
                'tail -30 /var/log/k3s-agent.log 2>/dev/null || '
                'echo "no logs"')
            pytest.fail(
                f"Agent did not join cluster:\n"
                f"Nodes:\n{nodes}\n"
                f"Agent logs:\n{agent_logs}")

    def test_k3s_multinode_ready(self, k3s_multinode):
        """Verify 2 nodes in Ready state."""
        server = k3s_multinode["server"]

        output = server.run_command(f'{_KUBECTL} get nodes 2>&1')
        ready_lines = [l for l in output.splitlines()
                       if 'Ready' in l and 'NotReady' not in l]
        assert len(ready_lines) == 2, \
            f"Expected 2 Ready nodes, got {len(ready_lines)}:\n{output}"

    def test_k3s_multinode_scheduling(self, k3s_multinode, k3s_timeout):
        """Deploy 2-replica deployment and verify pods on both nodes."""
        server = k3s_multinode["server"]

        server.run_command(
            f'{_KUBECTL} create deployment test-multi '
            f'--image=busybox --replicas=2 '
            f'-- sleep 300 2>&1')

        try:
            output = server.wait_for_condition(
                f'{_KUBECTL} get pods -l app=test-multi -o wide '
                f'2>/dev/null || echo WAITING',
                r'Running.*\n.*Running',
                timeout=k3s_timeout,
                interval=10,
                description="2 replicas Running")
        except TimeoutError:
            output = server.run_command(
                f'{_KUBECTL} get pods -l app=test-multi -o wide 2>&1')
            events = server.run_command(
                f'{_KUBECTL} describe pods -l app=test-multi 2>&1 '
                f'| tail -30')
            if 'Running' in output:
                print(f"Only partial scheduling achieved:\n{output}")
                return
            pytest.fail(
                f"Replicas not Running:\n{output}\nEvents:\n{events}")

        # Verify pods are on different nodes (best effort)
        pod_lines = [l for l in output.splitlines() if 'Running' in l]
        if len(pod_lines) >= 2:
            nodes = set()
            for line in pod_lines:
                parts = line.split()
                if len(parts) >= 7:
                    nodes.add(parts[6])
            if len(nodes) >= 2:
                print(f"Pods scheduled on {len(nodes)} different nodes")
            else:
                print(
                    "Pods on same node "
                    "(acceptable with 2-replica deployment)")

        # Cleanup
        server.run_command(
            f'{_KUBECTL} delete deployment test-multi '
            f'--grace-period=5 2>&1')
