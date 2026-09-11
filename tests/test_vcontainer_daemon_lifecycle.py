# SPDX-FileCopyrightText: Copyright (C) 2026 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
"""
Tests for vcontainer daemon (memres) lifecycle on the QEMU backend.

Covers:
- TestDaemonStartStop      - start/stop/status invariants
- TestDaemonRestart        - restart preserves state by default; --clean wipes it
- TestStateDiskIntegrity   - regression for daemon_stop SIGTERM truncation
                             (vrunner commits 664dc7e8 / 23438ae4 / 1c1fb6d1):
                             writes survive memres restart without ext4 journal
                             corruption, and tar-split layer reassembly works
                             across multiple vimport+restart cycles.
- TestActiveWorkloadStop   - daemon_stop while a write workload is in flight

Run with:
    pytest tests/test_vcontainer_daemon_lifecycle.py -v \\
        --vdkr-dir /tmp/vcontainer-standalone \\
        --oci-image /path/to/oci-dir

If --oci-image is not supplied the tests that need an OCI source will
attempt to construct one from alpine:latest via host-side skopeo. If
neither is available those tests are skipped.

Background:
    daemon_stop() in vrunner.sh used to sleep a fixed 2 seconds after
    sending ===SHUTDOWN=== and then SIGTERM QEMU. The guest's
    graceful_shutdown() routinely takes 5-30s under load (umount of
    /var/lib/containers/storage + ext4 journal commit), so the SIGTERM
    truncated the umount and left the state disk's journal half-committed.
    Subsequent sessions then hit:

        Error: reading blob sha256:<hash>: EOF
        Error: reading blob sha256:<hash>: file integrity checksum failed

    in tar-split layer reassembly. TestStateDiskIntegrity exists so a
    future regression of the poll-until-exit shutdown logic shows up
    here instead of in autobuilder push runs days later.
"""

import os
import shutil
import subprocess
import time
from pathlib import Path

import pytest


# ---------------------------------------------------------------------------
# Fixtures local to this test module
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def oci_image_or_skopeo(oci_image, tmp_path_factory):
    """
    Return a path to an OCI directory we can vimport from.

    Prefer the user-supplied --oci-image. Otherwise try to materialize
    one from alpine:latest via host-side skopeo. Skip if neither works.
    """
    if oci_image is not None:
        return oci_image

    if shutil.which("skopeo") is None:
        pytest.skip("No --oci-image supplied and skopeo not available on host")

    target = tmp_path_factory.mktemp("oci") / "alpine-oci"
    proc = subprocess.run(
        ["skopeo", "copy", "docker://alpine:latest", f"oci:{target}:latest"],
        capture_output=True, text=True, timeout=180,
    )
    if proc.returncode != 0:
        pytest.skip(f"skopeo could not fetch alpine: {proc.stderr.strip()}")
    return target


@pytest.fixture
def stopped_vpdmn(vpdmn):
    """
    Yield a vpdmn instance with memres guaranteed stopped at entry.
    Tests in this module mostly want a known clean start.
    """
    vpdmn.memres_stop()
    # tests that start memres are responsible for stopping it themselves;
    # leave memres in whatever state the test left it.
    yield vpdmn


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _wait_for_daemon_state(vpdmn, running, timeout=30, interval=0.5):
    """Poll memres status until it matches `running`, or timeout."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if vpdmn.is_memres_running() == running:
            return True
        time.sleep(interval)
    return False


def _image_id(vpdmn, name):
    """Return the IMAGE ID column for the given image name, or None."""
    result = vpdmn.images()
    if result.returncode != 0:
        return None
    for line in result.stdout.splitlines():
        # vpdmn images columns: REPOSITORY TAG IMAGE ID CREATED SIZE
        parts = line.split()
        if len(parts) >= 3 and name in parts[0]:
            return parts[2]
    return None


# ---------------------------------------------------------------------------
# TestDaemonStartStop
# ---------------------------------------------------------------------------

@pytest.mark.memres
class TestDaemonStartStop:
    """Start / stop / status invariants for the memres daemon."""

    def test_cold_start(self, stopped_vpdmn):
        """memres start from a stopped state succeeds and is reflected in status."""
        assert not stopped_vpdmn.is_memres_running()
        result = stopped_vpdmn.memres_start(timeout=180)
        assert result.returncode == 0, f"memres start failed: {result.stdout}"
        assert _wait_for_daemon_state(stopped_vpdmn, running=True), \
            "daemon not reported running after memres start"
        stopped_vpdmn.memres_stop(timeout=120)

    def test_stop_when_running(self, stopped_vpdmn):
        """memres stop after a successful start returns to not-running."""
        stopped_vpdmn.memres_start(timeout=180)
        assert stopped_vpdmn.is_memres_running()
        result = stopped_vpdmn.memres_stop(timeout=120)
        assert result.returncode == 0
        assert _wait_for_daemon_state(stopped_vpdmn, running=False), \
            "daemon still reported running after memres stop"

    def test_stop_when_not_running_is_idempotent(self, stopped_vpdmn):
        """memres stop on a stopped daemon must not error or block."""
        assert not stopped_vpdmn.is_memres_running()
        # Should return promptly with no error
        result = stopped_vpdmn.memres_stop(timeout=15)
        assert result.returncode == 0 or "not running" in result.stdout.lower()

    def test_status_when_stopped(self, stopped_vpdmn):
        """memres status on a stopped daemon must report not-running."""
        assert not stopped_vpdmn.is_memres_running()
        status = stopped_vpdmn.memres_status()
        # Either nonzero exit, or stdout says not running.
        assert status.returncode != 0 or "not running" in status.stdout.lower()


# ---------------------------------------------------------------------------
# TestDaemonRestart
# ---------------------------------------------------------------------------

@pytest.mark.memres
class TestDaemonRestart:
    """memres restart preserves state by default; --clean wipes it."""

    def test_restart_when_not_running(self, stopped_vpdmn):
        """restart on a stopped daemon should still leave it running."""
        assert not stopped_vpdmn.is_memres_running()
        result = stopped_vpdmn.run("memres", "restart", timeout=180)
        assert result.returncode == 0, f"restart failed: {result.stdout}"
        assert _wait_for_daemon_state(stopped_vpdmn, running=True)
        stopped_vpdmn.memres_stop(timeout=120)

    def test_restart_preserves_state(self, stopped_vpdmn, oci_image_or_skopeo):
        """vimport an image, restart (NOT --clean), verify image survives."""
        v = stopped_vpdmn
        v.memres_start(timeout=180)

        # Import a tagged image
        result = v.vimport(oci_image_or_skopeo, "persisttest:latest", timeout=180)
        assert result.returncode == 0, f"vimport failed: {result.stdout}"
        assert v.has_image("persisttest")

        # Restart without --clean
        result = v.run("memres", "restart", timeout=180)
        assert result.returncode == 0
        assert _wait_for_daemon_state(v, running=True)

        # Image should still be there
        assert v.has_image("persisttest"), \
            "image lost across memres restart without --clean"

        v.rmi("persisttest:latest")
        v.memres_stop(timeout=120)

    def test_restart_clean_wipes_state(self, stopped_vpdmn, oci_image_or_skopeo):
        """vimport an image, restart --clean, verify image is gone."""
        v = stopped_vpdmn
        v.memres_start(timeout=180)

        v.vimport(oci_image_or_skopeo, "wipetest:latest", timeout=180)
        assert v.has_image("wipetest")

        result = v.run("memres", "restart", "--clean", timeout=180)
        assert result.returncode == 0
        assert _wait_for_daemon_state(v, running=True)

        assert not v.has_image("wipetest"), \
            "image survived memres restart --clean"

        v.memres_stop(timeout=120)


# ---------------------------------------------------------------------------
# TestStateDiskIntegrity
# ---------------------------------------------------------------------------

@pytest.mark.memres
class TestStateDiskIntegrity:
    """
    Regression for daemon_stop()'s 2-second-sleep-then-SIGTERM bug
    (fixed in vrunner commits 664dc7e8 / 23438ae4 / 1c1fb6d1).

    Bug symptom: ext4 journal on the state disk is half-committed when
    QEMU is SIGTERMed mid-umount. Layer files appear correctly sized but
    have unwritten data extents. The next session's tar-split layer
    reassembly hits

        Error: reading blob sha256:<hash>: EOF
        Error: reading blob sha256:<hash>: file integrity checksum failed
               for "<file>"

    These tests deliberately exercise the vimport -> save -> restart ->
    vimport -> save cycle that triggered the corruption pre-fix.
    """

    def test_save_after_restart_preserves_blob_integrity(
            self, stopped_vpdmn, oci_image_or_skopeo, tmp_path):
        """
        vimport + save (clean), memres restart, save again. The second
        save must succeed - pre-fix it failed with EOF or CRC error on
        a tar-split-reassembled layer blob.
        """
        v = stopped_vpdmn
        v.memres_start(timeout=180)
        v.vimport(oci_image_or_skopeo, "integrity1:latest", timeout=180)

        save1 = tmp_path / "round1.tar"
        result = v.save(save1, "integrity1:latest", timeout=180)
        assert result.returncode == 0, f"first save failed: {result.stdout}"
        assert save1.exists() and save1.stat().st_size > 0

        # The trigger: restart cycles the state-disk save/restore path.
        # Pre-fix the SIGTERM during the stop step truncated the umount.
        result = v.run("memres", "restart", timeout=180)
        assert result.returncode == 0
        assert _wait_for_daemon_state(v, running=True)

        save2 = tmp_path / "round1-after-restart.tar"
        result = v.save(save2, "integrity1:latest", timeout=180)
        assert result.returncode == 0, (
            f"save after restart failed (state disk corruption?): "
            f"{result.stdout}"
        )
        assert save2.exists() and save2.stat().st_size > 0
        # Same content -> identical tarball size (podman is deterministic
        # when nothing has changed).
        assert save1.stat().st_size == save2.stat().st_size, \
            "save output size changed across restart - storage state diverged"

        v.rmi("integrity1:latest")
        v.memres_stop(timeout=120)

    def test_consecutive_vimport_restart_cycles(
            self, stopped_vpdmn, oci_image_or_skopeo, tmp_path):
        """
        Three rounds of (memres restart -> vimport -> save -> save again).
        Pre-fix this fails reliably on round 2 onwards.
        """
        v = stopped_vpdmn
        v.memres_start(timeout=180)

        for r in (1, 2, 3):
            if r > 1:
                # Restart cycles the disk; this was the bug trigger.
                result = v.run("memres", "restart", timeout=180)
                assert result.returncode == 0, \
                    f"round {r} restart failed: {result.stdout}"
                assert _wait_for_daemon_state(v, running=True)

            tag = f"cycle{r}:latest"
            result = v.vimport(oci_image_or_skopeo, tag, timeout=180)
            assert result.returncode == 0, \
                f"round {r} vimport failed: {result.stdout}"

            out1 = tmp_path / f"cycle{r}-a.tar"
            result = v.save(out1, tag, timeout=180)
            assert result.returncode == 0, \
                f"round {r} first save failed: {result.stdout}"

            out2 = tmp_path / f"cycle{r}-b.tar"
            result = v.save(out2, tag, timeout=180)
            assert result.returncode == 0, \
                f"round {r} second save failed: {result.stdout}"
            assert out1.stat().st_size == out2.stat().st_size, \
                f"round {r} save outputs differ in size"

        v.memres_stop(timeout=120)


# ---------------------------------------------------------------------------
# TestActiveWorkloadStop
# ---------------------------------------------------------------------------

@pytest.mark.memres
@pytest.mark.slow
class TestActiveWorkloadStop:
    """
    daemon_stop while real work is in flight.

    A bare 'sleep' test wouldn't exercise the bug path - the SIGTERM
    truncation only matters when the guest has uncommitted journal
    state. We trigger that by doing a vimport, then a save (both
    write paths through containers/storage), then stop and restart,
    and verify reads still work.
    """

    def test_stop_after_recent_writes_preserves_storage(
            self, stopped_vpdmn, oci_image_or_skopeo, tmp_path):
        """
        Heavy writes immediately before memres stop, then restart and
        read. Pre-fix this is essentially the original bug.
        """
        v = stopped_vpdmn
        v.memres_start(timeout=180)
        # Write traffic: vimport puts blobs into the state disk
        v.vimport(oci_image_or_skopeo, "writetest:latest", timeout=180)
        # Save triggers tar-split metadata regen, adding more journal traffic
        v.save(tmp_path / "before.tar", "writetest:latest", timeout=180)
        # Immediate stop, no wait
        result = v.memres_stop(timeout=120)
        assert result.returncode == 0
        # Bring it back up and read what we just wrote
        v.memres_start(timeout=180)
        result = v.save(tmp_path / "after.tar", "writetest:latest", timeout=180)
        assert result.returncode == 0, (
            f"save after stop+start failed (state disk corruption?): "
            f"{result.stdout}"
        )
        v.rmi("writetest:latest")
        v.memres_stop(timeout=120)
