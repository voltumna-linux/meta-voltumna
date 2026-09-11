# SPDX-FileCopyrightText: Copyright (C) 2026 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
LXC runtime tests — boot container-image-host with lxc installed and
exercise the LXC command-line lifecycle (create, start, attach, stop,
destroy).

The tests build container-image-host with CONTAINER_PROFILE=lxc, which
pulls in packagegroup-lxc (lxc + lxc-networking + lxc-templates). No
local.conf changes needed.

The download-template regression check (TestLxcDownloadTemplate) exists
specifically to catch the class of bug reported on the meta-virt list
on 2026-06-13 (Ferry Toth: "lxc: starting a container errors out"),
where a stale local patch to templates/lxc-download.in expanded an empty
${DOWNLOAD_TEMP} into `mktemp -p -d` and broke the download path before
any network call. The test invokes lxc-create with the download template
and asserts that the early mktemp error does not appear in the output,
even if the actual download itself fails (e.g. no network in the test
environment). That keeps the regression test useful in air-gapped CI
without requiring outbound network from the qemu guest.

Run:
    pytest tests/test_lxc_runtime.py -v --poky-dir /opt/bruce/poky

Options:
    --boot-timeout      QEMU boot timeout (default: 120s)
    --no-kvm            Disable KVM acceleration
    --machine           QEMU MACHINE (default: qemux86-64)
"""

import os
import subprocess
import tempfile
import time
from pathlib import Path

import pytest

try:
    import pexpect
    PEXPECT_AVAILABLE = True
except ImportError:
    PEXPECT_AVAILABLE = False


pytestmark = [
    pytest.mark.skipif(not PEXPECT_AVAILABLE, reason="pexpect not installed"),
    pytest.mark.lxc,
    pytest.mark.boot,
]


# ---------------------------------------------------------------------------
# Helpers (mirror test_incus_runtime.py conventions so the suites read alike)
# ---------------------------------------------------------------------------

def _run_bitbake(build_dir, recipe, extra_vars=None, timeout=3600):
    """Run bitbake with optional variable overrides via -R conf file."""
    bb_cmd = "bitbake"
    conf_file = None
    if extra_vars:
        conf_file = tempfile.NamedTemporaryFile(
            mode='w', suffix='.conf', prefix='pytest-lxc-',
            dir=str(build_dir / "conf"), delete=False)
        for var, val in extra_vars.items():
            conf_file.write(f'{var} = "{val}"\n')
        conf_file.close()
        bb_cmd += f" -R {conf_file.name}"
    bb_cmd += f" {recipe}"
    poky_dir = build_dir.parent
    full_cmd = (
        f"bash -c 'cd {poky_dir} && "
        f"source oe-init-build-env {build_dir} >/dev/null 2>&1 && {bb_cmd}'"
    )
    try:
        return subprocess.run(full_cmd, shell=True, cwd=build_dir,
                              timeout=timeout, capture_output=True, text=True)
    finally:
        if conf_file:
            os.unlink(conf_file.name)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def lxc_image(request):
    """Build container-image-host with the lxc container profile.

    CONTAINER_PROFILE=lxc resolves via conf/distro/include/meta-virt-container-lxc.inc
    to VIRTUAL-RUNTIME_container_engine=lxc, which container-image-host.bb
    treats as a signal to install packagegroup-lxc (lxc + lxc-networking
    + lxc-templates). Same mechanism the incus / podman / k3s profiles
    use, so the test exercises the same code path real users would take.
    """
    poky_dir = Path(request.config.getoption("--poky-dir"))
    bd = request.config.getoption("--build-dir")
    build_dir = Path(bd) if bd else poky_dir / "build"
    result = _run_bitbake(
        build_dir, "container-image-host",
        extra_vars={
            "CONTAINER_PROFILE": "lxc",
        },
    )
    if result.returncode != 0:
        pytest.fail(f"container-image-host with lxc failed to build: {result.stderr}")


@pytest.fixture(scope="module")
def lxc_qemu(request, lxc_image):
    """Boot container-image-host in QEMU, return a logged-in pexpect session."""
    machine = request.config.getoption("--machine", default="qemux86-64")
    boot_timeout = int(request.config.getoption("--boot-timeout", default="120"))
    no_kvm = request.config.getoption("--no-kvm", default=False)

    poky_dir = Path(request.config.getoption("--poky-dir"))
    bd = request.config.getoption("--build-dir")
    builddir = str(Path(bd) if bd else poky_dir / "build")

    kvm_opt = "" if no_kvm else "kvm"
    cmd = (
        f"runqemu {machine} container-image-host ext4 nographic slirp "
        f"{kvm_opt} qemuparams=\"-m 4096\""
    )

    # Route runqemu's full output to /tmp so a boot failure leaves a
    # diagnosable trail. pexpect's default 100-char-truncated "before"
    # buffer hides the actual error from pytest's traceback otherwise.
    log_path = Path(tempfile.gettempdir()) / "test_lxc_runtime-runqemu.log"
    log_path.write_text("")  # truncate from any prior run
    log_fp = log_path.open("w")
    child = pexpect.spawn(
        f"bash -c 'cd {poky_dir} && source oe-init-build-env {builddir} "
        f">/dev/null 2>&1 && {cmd}'",
        timeout=boot_timeout, encoding="utf-8", logfile=log_fp,
    )

    try:
        child.expect(r"login:", timeout=boot_timeout)
    except pexpect.EOF:
        log_fp.flush()
        log_fp.close()
        # Drop the last 60 lines of the runqemu log into the failure
        # message so the actual cause is visible without grepping.
        tail = "\n".join(log_path.read_text().splitlines()[-60:])
        pytest.fail(
            f"runqemu exited before login prompt. Full log at {log_path}.\n"
            f"Tail:\n{tail}"
        )
    child.sendline("root")
    child.expect(r"root@.*[:~#]", timeout=30)

    # Suppress shell-integration escape sequences that interfere with
    # pexpect matchers (same trick as test_incus_runtime / test_xen_runtime).
    child.sendline("export TERM=dumb")
    child.expect(r"root@.*[:~#]", timeout=10)

    yield child

    child.sendline("poweroff")
    try:
        child.expect(pexpect.EOF, timeout=30)
    except pexpect.TIMEOUT:
        child.terminate(force=True)


def run_cmd(child, cmd, timeout=60):
    """Run a shell command in the guest and return (stdout, rc)."""
    marker = f"__MARKER_{time.monotonic_ns()}__"
    child.sendline(f"{cmd}; echo {marker} $?")
    child.expect(marker + r" (\d+)", timeout=timeout)
    output = child.before.strip()
    rc = int(child.match.group(1))
    child.expect(r"root@.*[:~#]", timeout=10)
    return output, rc


# ---------------------------------------------------------------------------
# Sanity — lxc tooling present and functional
# ---------------------------------------------------------------------------

class TestLxcInstalled:
    """Confirm lxc is installed and the basic commands report a version."""

    def test_lxc_create_present(self, lxc_qemu):
        output, rc = run_cmd(lxc_qemu, "command -v lxc-create")
        assert rc == 0, f"lxc-create not installed: {output}"

    def test_lxc_start_present(self, lxc_qemu):
        output, rc = run_cmd(lxc_qemu, "command -v lxc-start")
        assert rc == 0, f"lxc-start not installed: {output}"

    def test_lxc_version(self, lxc_qemu):
        output, rc = run_cmd(lxc_qemu, "lxc-create --version")
        assert rc == 0, f"lxc-create --version failed: {output}"


# ---------------------------------------------------------------------------
# Regression: the lxc-download.in mktemp bug from list thread #11808
# ---------------------------------------------------------------------------

class TestLxcDownloadTemplate:
    """Regression for the templates-actually-create-DOWNLOAD_TEMP-directory
    patch breakage.

    The bug was: when ${DOWNLOAD_TEMP} is unset (the common case for
    `lxc-create --template download`), the patched else branch expanded
    to `mktemp -p  -d`, which the shell parses as `-d` being the argument
    to `-p` rather than its own flag. mktemp then reports:

        mktemp: failed to create file via template '-d/tmp.XXXXXXXXXX':
        No such file or directory

    and lxc-create exits before any network call.

    We don't care whether the download itself succeeds here — in a test
    environment without outbound network, it won't, and that's fine.
    We only care that the early mktemp parse never happens. If it does,
    that *exact* error string surfaces, and that string failing to appear
    is what we assert.
    """

    BAD_MKTEMP_ERROR = "mktemp: failed to create file via template '-d"

    def test_download_template_no_mktemp_error(self, lxc_qemu):
        """lxc-create with the download template must not emit the broken
        mktemp invocation even when the actual download fails."""
        # The specific dist/release/arch values don't matter — even an
        # invalid combination still exercises the early mktemp path
        # before any HTTP request. We pick a plausibly-real combo so the
        # test stays meaningful if a future change adds an early
        # validation step on the args.
        cmd = (
            "lxc-create --name test-download --template download -- "
            "--dist ubuntu --release noble --arch amd64 2>&1"
        )
        output, _rc = run_cmd(lxc_qemu, cmd, timeout=120)
        assert self.BAD_MKTEMP_ERROR not in output, (
            f"lxc-download.in DOWNLOAD_TEMP regression — early mktemp error "
            f"surfaced.\nFull output:\n{output}"
        )
        # Clean up whatever partial state lxc-create may have left behind
        # so the next test starts clean. Ignore rc — there may be nothing
        # to destroy.
        run_cmd(lxc_qemu, "lxc-destroy --name test-download --force", timeout=30)


# ---------------------------------------------------------------------------
# Network-required path — exercise the full download+create flow
# ---------------------------------------------------------------------------

@pytest.mark.network
class TestLxcContainerLifecycle:
    """End-to-end create/start/attach/stop/destroy against a real download.

    Marked @network because lxc-create --template download fetches from
    images.linuxcontainers.org. Skipped on offline runners. The regression
    test above runs without network and is the primary guard against
    Ferry's bug.
    """

    NAME = "test-lxc-lifecycle"

    def test_create_alpine_via_download(self, lxc_qemu):
        # Best-effort cleanup of a stale container from a previous run that
        # was killed before test_destroy got to run. Ignore rc — the common
        # case is "no such container" and that's exactly what we want.
        run_cmd(lxc_qemu,
                f"lxc-destroy --force --name {self.NAME} >/dev/null 2>&1 || true",
                timeout=30)
        cmd = (
            f"lxc-create --name {self.NAME} --template download -- "
            f"--dist alpine --release edge --arch amd64"
        )
        output, rc = run_cmd(lxc_qemu, cmd, timeout=600)
        if rc == 0:
            return
        # Only skip when the failure is clearly the download / network path.
        # "Container already exists" or other config errors must fail loudly
        # — silently skipping them masks real regressions (the whole point
        # of the bug Ferry reported).
        network_markers = (
            "Failed to download",
            "couldn't be found",
            "bad address",
            "Temporary failure in name resolution",
            "Network is unreachable",
            "No route to host",
            "Connection refused",
            "Connection timed out",
            "wget: error getting response",
            "wget: can't connect",
            "Unable to fetch GPG key",
        )
        if any(m in output for m in network_markers):
            pytest.skip(
                f"lxc-create download failed (network unreachable): "
                f"{output[:400]}"
            )
        pytest.fail(
            f"lxc-create failed (rc={rc}) with non-network error:\n{output}"
        )

    def test_start(self, lxc_qemu):
        # Pre-flight environment checks. lxc-start has a habit of aborting
        # with a generic "Received container state ABORTING" message that
        # gives no hint of which precondition (bridge up, lxc-net active,
        # kernel features present) actually failed. Surface each piece in
        # the failure path so post-mortem doesn't require re-booting and
        # poking around by hand.
        net_out, _ = run_cmd(lxc_qemu, "systemctl is-active lxc-net.service")
        bridge_out, bridge_rc = run_cmd(
            lxc_qemu, "ip -o link show lxcbr0 2>&1 | head -1")

        # Capture lxc-start's own log alongside the user-visible stderr so
        # a failure message contains the real abort cause without needing
        # a re-run. The `( … exit $LXC_RC )` subshell preserves lxc-start's
        # exit code for the marker-based run_cmd harness — `exit` outside
        # a subshell would kill the guest's login shell, which respawns
        # getty and breaks every subsequent test in the suite.
        output, rc = run_cmd(
            lxc_qemu,
            f"lxc-start --name {self.NAME} --logfile /tmp/lxc-start.log "
            f"--logpriority DEBUG 2>&1 ; LXC_RC=$? ; "
            f"echo '--- lxc-start rc=' $LXC_RC ' ---' ; "
            f"echo '--- lxc-start.log tail ---' ; "
            f"tail -40 /tmp/lxc-start.log ; "
            f"( exit $LXC_RC )",
            timeout=90,
        )
        assert rc == 0, (
            f"lxc-start failed.\n"
            f"  lxc-net.service: {net_out!r}\n"
            f"  lxcbr0 link (rc={bridge_rc}): {bridge_out!r}\n"
            f"  full output:\n{output}"
        )
        # Give the container a moment to come up
        run_cmd(lxc_qemu, "sleep 3")

    def test_running(self, lxc_qemu):
        output, rc = run_cmd(lxc_qemu, f"lxc-ls --running -1")
        assert self.NAME in output, f"container not running: {output}"

    def test_attach_runs_command(self, lxc_qemu):
        # lxc-attach returns the exit code of the inner command, so
        # check the inner command's output rather than rc alone.
        output, _rc = run_cmd(
            lxc_qemu,
            f"lxc-attach --name {self.NAME} -- cat /etc/os-release",
            timeout=30,
        )
        assert "alpine" in output.lower(), (
            f"expected alpine os-release inside container, got: {output}"
        )

    def test_stop(self, lxc_qemu):
        output, rc = run_cmd(lxc_qemu, f"lxc-stop --name {self.NAME}",
                             timeout=60)
        assert rc == 0, f"lxc-stop failed: {output}"

    def test_destroy(self, lxc_qemu):
        output, rc = run_cmd(lxc_qemu, f"lxc-destroy --name {self.NAME}",
                             timeout=60)
        assert rc == 0, f"lxc-destroy failed: {output}"
