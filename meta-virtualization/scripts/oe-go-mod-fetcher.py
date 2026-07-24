#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
#
# go-dep processor
#
# Copyright (C) 2025 Bruce Ashfield
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

"""
Go Module Git Fetcher - Hybrid Architecture
Version 3.0.0 - Complete rewrite using Go download for discovery + git builds
Author: Bruce Ashfield
Description: Use Go's download for discovery, build from git sources

ARCHITECTURE:
Phase 1: Discovery - Use 'go mod download' + filesystem walk to get correct module paths
Phase 2: Recipe Generation - Generate BitBake recipe with git:// SRC_URI entries
Phase 3: Cache Building - Build module cache from git sources during do_create_module_cache

This approach eliminates:
- Complex go list -m -json parsing
- Manual go.sum parsing and augmentation
- Parent module detection heuristics
- Version path manipulation (/v2+/v3+ workarounds)
- Module path normalization bugs

Instead we:
- Let Go download modules to temporary cache (discovery only)
- Walk filesystem to get CORRECT module paths (no parsing!)
- Extract VCS info from .info files
- Fetch git repositories for each module
- Build module cache from git during BitBake build

CHANGELOG v3.0.0:
- Complete architectural rewrite
- Removed all go list and go.sum parsing logic (4000+ lines)
- Implemented 3-phase hybrid approach
- Discovery uses go mod download + filesystem walk
- Module paths from filesystem, not from go list (no more /v3 stripping bugs!)
- Builds entirely from git sources
- Compatible with oe-core's gomod:// fetcher (same cache structure)
"""

import argparse
import concurrent.futures
import csv
import fnmatch
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import threading
import zipfile
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple
from datetime import datetime, timedelta, timezone

VERSION = "3.0.0"
LOG_PATH: Optional[Path] = None

# =============================================================================
# BitBake Task Templates
# =============================================================================


class Tee(io.TextIOBase):
    """Write data to multiple text streams."""

    def __init__(self, *streams: io.TextIOBase) -> None:
        self.streams = streams

    def write(self, data: str) -> int:
        for stream in self.streams:
            stream.write(data)
        return len(data)

    def flush(self) -> None:
        for stream in self.streams:
            stream.flush()

def parse_go_sum(go_sum_path: Path) -> Tuple[Set[Tuple[str, str]], Set[Tuple[str, str]]]:
    """
    Parse go.sum to find modules that need source code.

    Returns:
        Tuple of (modules_needing_source, indirect_only_modules)
        - modules_needing_source: Modules with source code entries (need .zip files)
        - indirect_only_modules: Modules that only have /go.mod entries (only need .mod files)
    """
    def sanitize_module_name(name):
        """Remove quotes from module names"""
        if not name:
            return name
        stripped = name.strip()
        if len(stripped) >= 2 and stripped[0] == '"' and stripped[-1] == '"':
            return stripped[1:-1]
        return stripped

    modules_with_source: Set[Tuple[str, str]] = set()
    modules_with_gomod_only: Set[Tuple[str, str]] = set()

    if not go_sum_path.exists():
        return (modules_with_source, modules_with_gomod_only)

    # First pass: collect all entries
    all_entries = {}
    with go_sum_path.open() as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('//'):
                continue
            parts = line.split()
            if len(parts) != 3:
                continue

            module_path, version, _ = parts
            module_path = sanitize_module_name(module_path)

            # Track whether this entry is for go.mod or source
            is_gomod_entry = version.endswith('/go.mod')

            # Strip /go.mod suffix for key
            base_version = version[:-7] if is_gomod_entry else version
            key = (module_path, base_version)

            if key not in all_entries:
                all_entries[key] = {'has_source': False, 'has_gomod': False}

            if is_gomod_entry:
                all_entries[key]['has_gomod'] = True
            else:
                all_entries[key]['has_source'] = True

    # Second pass: categorize modules
    for key, entry_types in all_entries.items():
        if entry_types['has_source']:
            modules_with_source.add(key)
            continue

        if entry_types['has_gomod']:
            modules_with_gomod_only.add(key)
            # Note: We no longer add indirect-only modules to modules_with_source.
            # The native build succeeds without their .zip files - only .mod files are needed.
            # Adding them caused the generator to resolve ~1000 extra modules unnecessarily.

    return (modules_with_source, modules_with_gomod_only)


def collect_modules_via_go_list(source_dir: Path) -> Set[Tuple[str, str]]:
    """
    Use `go list -m -json all` to discover modules that may not appear in go.sum.
    """
    env = os.environ.copy()
    env.setdefault('GOPROXY', 'https://proxy.golang.org')
    if CURRENT_GOMODCACHE:
        env['GOMODCACHE'] = CURRENT_GOMODCACHE

    try:
        result = subprocess.run(
            ['go', 'list', '-m', '-json', 'all'],
            cwd=source_dir,
            capture_output=True,
            text=True,
            check=True,
            env=env,
        )
    except subprocess.CalledProcessError:
        return set()

    data = result.stdout
    modules: Set[Tuple[str, str]] = set()
    decoder = json.JSONDecoder()
    idx = 0
    length = len(data)

    while idx < length:
        while idx < length and data[idx].isspace():
            idx += 1
        if idx >= length:
            break
        try:
            obj, end = decoder.raw_decode(data, idx)
        except json.JSONDecodeError:
            break
        idx = end

        path = obj.get('Path') or ''
        if not path or obj.get('Main'):
            continue

        version = obj.get('Version') or ''
        replace = obj.get('Replace')
        if replace:
            path = replace.get('Path', path) or path
            version = replace.get('Version', version) or version

        if not version or version == 'none':
            continue

        modules.add((path, version))

    return modules


def go_mod_download(module_path: str, version: str) -> bool:
    """Download a specific module version into the current GOMODCACHE."""
    if not CURRENT_GOMODCACHE or not CURRENT_SOURCE_DIR:
        return False

    key = (module_path, version)
    if key in DOWNLOADED_MODULES:
        return module_path

    env = os.environ.copy()
    env.setdefault('GOPROXY', 'https://proxy.golang.org')
    env['GOMODCACHE'] = CURRENT_GOMODCACHE

    try:
        subprocess.run(
            ['go', 'mod', 'download', f'{module_path}@{version}'],
            cwd=str(CURRENT_SOURCE_DIR),
            env=env,
            capture_output=True,
            text=True,
            check=True,
            timeout=GO_CMD_TIMEOUT,
        )
        DOWNLOADED_MODULES.add(key)
        return True
    except subprocess.TimeoutExpired as e:
        print(f"  ❌ go mod download timed out for {module_path}@{version} after {GO_CMD_TIMEOUT}s")
        return False
    except subprocess.CalledProcessError as e:
        stderr = (e.stderr or '').strip()
        if stderr:
            lower = stderr.lower()
            network_signals = [
                "lookup ", "dial tcp", "connection refused",
                "network is unreachable", "tls handshake timeout",
                "socket: operation not permitted"
            ]
            if any(signal in lower for signal in network_signals):
                global NETWORK_FAILURE_DETECTED
                NETWORK_FAILURE_DETECTED = True
                raise RuntimeError(
                    f"Network failure while downloading {module_path}@{version}: {stderr}"
                ) from e
        print(f"  ⚠️  go mod download failed for {module_path}@{version}: {stderr}")
        return False


SCRIPT_DIR = Path(__file__).resolve().parent
CACHE_BASE_DIR = SCRIPT_DIR / "data"  # Default to scripts/data for JSON caches
DATA_DIR = CACHE_BASE_DIR
CLONE_CACHE_DIR = SCRIPT_DIR / ".cache" / "repos"  # Repository clone cache
VERIFY_BASE_DIR = CACHE_BASE_DIR / ".verify"
LS_REMOTE_CACHE_PATH = DATA_DIR / "ls-remote-cache.json"
VERIFY_COMMIT_CACHE_PATH = DATA_DIR / "verify-cache.json"
MODULE_REPO_OVERRIDES_PATH = DATA_DIR / "repo-overrides.json"
# Manual overrides file - tracked in git, for permanent overrides when discovery fails
MANUAL_OVERRIDES_PATH = SCRIPT_DIR / "data" / "manual-overrides.json"

LS_REMOTE_CACHE: Dict[Tuple[str, str], Optional[str]] = {}
LS_REMOTE_CACHE_DIRTY = False

MODULE_METADATA_CACHE_PATH = DATA_DIR / "module-cache.json"
MODULE_METADATA_CACHE: Dict[Tuple[str, str], Dict[str, str]] = {}
MODULE_METADATA_CACHE_DIRTY = False

VANITY_URL_CACHE_PATH = DATA_DIR / "vanity-url-cache.json"
VANITY_URL_CACHE: Dict[str, Optional[str]] = {}
VANITY_URL_CACHE_DIRTY = False

CURRENT_GOMODCACHE: Optional[str] = None
CURRENT_SOURCE_DIR: Optional[Path] = None
TEMP_GOMODCACHES: List[Path] = []
FAILED_MODULE_PATHS: Set[str] = set()
FAILED_MODULE_ENTRIES: Set[Tuple[str, str]] = set()
DOWNLOADED_MODULES: Set[Tuple[str, str]] = set()
NETWORK_FAILURE_DETECTED: bool = False
SKIPPED_MODULES: Dict[Tuple[str, str], str] = {}
VERBOSE_MODE: bool = False  # Set from command-line args

def _record_skipped_module(module_path: str, version: str, reason: str) -> None:
    SKIPPED_MODULES[(module_path, version)] = reason

GO_CMD_TIMEOUT = 180  # seconds
GIT_CMD_TIMEOUT = 90  # seconds

VERIFY_REPO_CACHE: Dict[str, Path] = {}
VERIFY_REPO_LOCKS: Dict[str, threading.Lock] = {}  # Per-repository locks for parallel verification
VERIFY_REPO_LOCKS_LOCK = threading.RLock()  # REENTRANT lock to allow same thread to acquire multiple times
VERIFY_REPO_BRANCHES: Dict[str, List[str]] = {}  # Cache branch lists per repo to avoid repeated ls-remote
VERIFY_RESULTS: Dict[Tuple[str, str], bool] = {}
VERIFY_COMMIT_CACHE: Dict[str, bool] = {}  # Legacy format: key -> bool
VERIFY_COMMIT_CACHE_V2: Dict[str, Dict[str, any]] = {}  # New format: key -> {verified: bool, timestamp: str, last_check: str}
VERIFY_COMMIT_CACHE_DIRTY = False
VERIFY_ENABLED = False  # Set to True when verification is active
VERIFY_CACHE_MAX_AGE_DAYS = 30  # Re-verify commits older than this
VERIFY_DETECTED_BRANCHES: Dict[Tuple[str, str], str] = {}  # (url, commit) -> branch_name
VERIFY_FALLBACK_COMMITS: Dict[Tuple[str, str], str] = {}  # Maps (url, original_commit) -> fallback_commit
VERIFY_FULL_REPOS: Set[str] = set()  # Track repos that have been fetched with full history
VERIFY_CORRECTIONS_APPLIED = False  # Track if any commit corrections were made
MODULE_REPO_OVERRIDES: Dict[Tuple[str, Optional[str]], str] = {}  # Dynamic overrides from --set-repo
MODULE_REPO_OVERRIDES_DIRTY = False
MANUAL_OVERRIDES: Dict[Tuple[str, Optional[str]], str] = {}  # Git-tracked overrides from manual-overrides.json

# REPO_OVERRIDES kept for backwards compatibility but no longer used for hardcoded values.
# Manual overrides go in data/manual-overrides.json which is tracked in git.
REPO_OVERRIDES: Dict[str, List[str]] = {}


def _normalise_override_key(module_path: str, version: Optional[str]) -> Tuple[str, Optional[str]]:
    module = module_path.strip()
    ver = version.strip() if version else None
    if not module:
        raise ValueError("module path for override cannot be empty")
    return module, ver


def _parse_override_spec(module_spec: str) -> Tuple[str, Optional[str]]:
    if '@' in module_spec:
        module_path, version = module_spec.split('@', 1)
        version = version or None
    else:
        module_path, version = module_spec, None
    return module_path.strip(), version.strip() if version else None


def repo_override_candidates(module_path: str, version: Optional[str] = None) -> List[str]:
    """
    Get repository URL override candidates for a module.

    Priority order:
    1. Dynamic overrides (--set-repo, stored in repo-overrides.json) - version-specific
    2. Dynamic overrides - wildcard (no version)
    3. Manual overrides (manual-overrides.json, tracked in git) - version-specific
    4. Manual overrides - wildcard
    5. Legacy REPO_OVERRIDES dict (for backwards compatibility)
    """
    overrides: List[str] = []
    key = _normalise_override_key(module_path, version)
    wildcard_key = _normalise_override_key(module_path, None)

    # Dynamic overrides first (highest priority - user can override manual)
    dynamic_specific = MODULE_REPO_OVERRIDES.get(key)
    if dynamic_specific:
        overrides.append(dynamic_specific)

    dynamic_default = MODULE_REPO_OVERRIDES.get(wildcard_key)
    if dynamic_default and dynamic_default not in overrides:
        overrides.append(dynamic_default)

    # Manual overrides next (git-tracked, for permanent fixes)
    manual_specific = MANUAL_OVERRIDES.get(key)
    if manual_specific and manual_specific not in overrides:
        overrides.append(manual_specific)

    manual_default = MANUAL_OVERRIDES.get(wildcard_key)
    if manual_default and manual_default not in overrides:
        overrides.append(manual_default)

    # Legacy hardcoded overrides last (backwards compat)
    for candidate in REPO_OVERRIDES.get(module_path, []):
        if candidate not in overrides:
            overrides.append(candidate)

    return overrides


def configure_cache_paths(cache_dir: Optional[str], clone_cache_dir: Optional[str] = None) -> None:
    """
    Configure cache file locations.

    Args:
        cache_dir: Directory for JSON metadata caches (default: scripts/data)
        clone_cache_dir: Directory for git repository clones (default: scripts/.cache/repos)
    """
    global CACHE_BASE_DIR, DATA_DIR, CLONE_CACHE_DIR
    global LS_REMOTE_CACHE_PATH, MODULE_METADATA_CACHE_PATH, VANITY_URL_CACHE_PATH
    global VERIFY_COMMIT_CACHE_PATH, MODULE_REPO_OVERRIDES_PATH

    # Configure JSON metadata cache directory
    if cache_dir:
        CACHE_BASE_DIR = Path(cache_dir).resolve()
    else:
        CACHE_BASE_DIR = SCRIPT_DIR / "data"  # Default to scripts/data

    CACHE_BASE_DIR.mkdir(parents=True, exist_ok=True)
    DATA_DIR = CACHE_BASE_DIR  # cache_dir IS the data directory now

    LS_REMOTE_CACHE_PATH = DATA_DIR / "ls-remote-cache.json"
    MODULE_METADATA_CACHE_PATH = DATA_DIR / "module-cache.json"
    VANITY_URL_CACHE_PATH = DATA_DIR / "vanity-url-cache.json"
    VERIFY_COMMIT_CACHE_PATH = DATA_DIR / "verify-cache.json"
    MODULE_REPO_OVERRIDES_PATH = DATA_DIR / "repo-overrides.json"

    global VERIFY_BASE_DIR
    VERIFY_BASE_DIR = CACHE_BASE_DIR / ".verify"
    VERIFY_BASE_DIR.mkdir(parents=True, exist_ok=True)

    # Configure git clone cache directory
    if clone_cache_dir:
        CLONE_CACHE_DIR = Path(clone_cache_dir).resolve()
    else:
        CLONE_CACHE_DIR = SCRIPT_DIR / ".cache" / "repos"  # Default to scripts/.cache/repos

    CLONE_CACHE_DIR.mkdir(parents=True, exist_ok=True)

    VERIFY_COMMIT_CACHE.clear()
    load_verify_commit_cache()
    MODULE_REPO_OVERRIDES.clear()
    load_repo_overrides()
    load_manual_overrides()

    global VERIFY_REPO_CACHE
    VERIFY_REPO_CACHE = {}


def ensure_path_is_writable(path: Path) -> None:
    """
    Attempt to create and delete a small file to verify write access. Exit with
    a clear error if the path is not writable.
    """
    path.mkdir(parents=True, exist_ok=True)
    probe = path / ".oe-go-mod-fetcher-permcheck"
    try:
        with open(probe, "w") as fh:
            fh.write("")
    except Exception as exc:
        print(f"❌ GOMODCACHE is not writable: {path} ({exc})")
        print("   Fix permissions (e.g. chown/chmod) or pass a writable --gomodcache path.")
        sys.exit(1)
    finally:
        try:
            probe.unlink()
        except Exception:
            pass

def _normalize_url(url: str) -> str:
    url = url.strip()
    if url.startswith("git://"):
        url = "https://" + url[6:]
    if url.endswith(".git"):
        url = url[:-4]
    return url


def _url_allowed_for_module(module_path: str, url: str, version: Optional[str] = None) -> bool:
    url = _normalize_url(url)
    overrides = repo_override_candidates(module_path, version)
    if not overrides:
        return True
    normalized_overrides = {_normalize_url(o) for o in overrides}
    return url in normalized_overrides


def prune_metadata_cache() -> None:
    """
    Remove stale metadata entries that no longer satisfy override policies or
    contain obviously invalid data. This prevents old .inc state from
    re-introducing bad repositories during bootstrap.
    """
    global MODULE_METADATA_CACHE_DIRTY

    removed = False
    for key in list(MODULE_METADATA_CACHE.keys()):
        module_path, version = key
        entry = MODULE_METADATA_CACHE.get(key) or {}
        vcs_url = entry.get('vcs_url', '')
        commit = entry.get('commit', '')

        if not vcs_url or not commit:
            MODULE_METADATA_CACHE.pop(key, None)
            removed = True
            continue

        if len(commit) != 40 or not re.fullmatch(r'[0-9a-fA-F]{40}', commit):
            MODULE_METADATA_CACHE.pop(key, None)
            removed = True
            continue

        if not _url_allowed_for_module(module_path, vcs_url, version):
            MODULE_METADATA_CACHE.pop(key, None)
            removed = True
            continue

    if removed:
        MODULE_METADATA_CACHE_DIRTY = True


def _verify_repo_dir(vcs_url: str) -> Path:
    # Quick check without lock (optimization)
    if vcs_url in VERIFY_REPO_CACHE:
        return VERIFY_REPO_CACHE[vcs_url]

    # Use master lock to serialize repo initialization
    with VERIFY_REPO_LOCKS_LOCK:
        # Double-check after acquiring lock
        if vcs_url in VERIFY_REPO_CACHE:
            return VERIFY_REPO_CACHE[vcs_url]

        repo_hash = hashlib.sha256(vcs_url.encode()).hexdigest()
        repo_dir = VERIFY_BASE_DIR / repo_hash
        git_dir = repo_dir / "repo"
        git_dir.mkdir(parents=True, exist_ok=True)

        env = os.environ.copy()
        env.setdefault("GIT_TERMINAL_PROMPT", "0")
        env.setdefault("GIT_ASKPASS", "true")

        if not (git_dir / "config").exists():
            subprocess.run([
                "git", "init", "--bare"
            ], cwd=str(git_dir), check=True, capture_output=True, env=env)
            subprocess.run([
                "git", "remote", "add", "origin", vcs_url
            ], cwd=str(git_dir), check=True, capture_output=True, env=env)
        else:
            subprocess.run([
                "git", "remote", "set-url", "origin", vcs_url
            ], cwd=str(git_dir), check=False, capture_output=True, env=env)

        VERIFY_REPO_CACHE[vcs_url] = git_dir

        # Create a per-repo lock while we still hold the master lock
        if vcs_url not in VERIFY_REPO_LOCKS:
            VERIFY_REPO_LOCKS[vcs_url] = threading.Lock()

        return git_dir


def _find_fallback_commit(vcs_url: str, version: str, timestamp: str = "") -> Optional[Tuple[str, str]]:
    """
    Find a fallback commit when the proxy commit doesn't exist.

    Strategy:
    1. For pseudo-versions with timestamp: find commit near that date on default branch
    2. Otherwise: use latest commit on default branch (main/master)

    Returns: (commit_hash, branch_name) or None if failed
    """
    import re
    from datetime import datetime

    env = os.environ.copy()
    env.setdefault("GIT_TERMINAL_PROMPT", "0")
    env.setdefault("GIT_ASKPASS", "true")

    # Extract timestamp from pseudo-version: v0.0.0-YYYYMMDDHHMMSS-hash
    target_date = None
    if timestamp:
        try:
            target_date = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
        except Exception:
            pass

    if not target_date:
        # Try to extract from pseudo-version format
        match = re.match(r'v\d+\.\d+\.\d+-(\d{14})-[0-9a-f]+', version)
        if match:
            date_str = match.group(1)  # YYYYMMDDHHMMSS
            try:
                target_date = datetime.strptime(date_str, '%Y%m%d%H%M%S')
            except Exception:
                pass

    # Get default branch
    try:
        result = subprocess.run(
            ["git", "ls-remote", "--symref", vcs_url, "HEAD"],
            capture_output=True,
            text=True,
            timeout=30,
            env=env,
        )
        if result.returncode == 0 and result.stdout:
            # Parse: ref: refs/heads/main  HEAD
            for line in result.stdout.split('\n'):
                if line.startswith('ref:'):
                    default_branch = line.split()[1].replace('refs/heads/', '')
                    break
            else:
                default_branch = 'main'  # Fallback
        else:
            default_branch = 'main'
    except Exception:
        default_branch = 'main'

    # Get commits on default branch
    try:
        if target_date:
            # Find commit closest to target date
            # We need to clone the repo to access commit history with dates

            # NOTE: Do NOT acquire per-repo lock here - our caller already holds it!
            # _find_fallback_commit is only called from within verify_commit_accessible,
            # which has already acquired the per-repo lock for this vcs_url.

            # Get the repo dir (cached, won't re-initialize)
            repo_dir = VERIFY_REPO_CACHE.get(vcs_url)
            if not repo_dir:
                # Shouldn't happen (verify_commit_accessible calls _verify_repo_dir first)
                # but be defensive
                repo_dir = _verify_repo_dir(vcs_url)

            # Fetch the default branch (caller holds lock, so this is safe)
            try:
                subprocess.run(
                    ["git", "fetch", "origin", f"{default_branch}:refs/remotes/origin/{default_branch}"],
                    cwd=str(repo_dir),
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=60,
                    env=env,
                )
            except subprocess.CalledProcessError:
                # Fallback to latest if fetch fails
                pass

            # Use git log with --until to find commit at or before target date
            # Format: YYYY-MM-DD HH:MM:SS
            date_str = target_date.strftime('%Y-%m-%d %H:%M:%S')
            try:
                result = subprocess.run(
                    ["git", "log", "-1", "--format=%H", f"--until={date_str}", f"origin/{default_branch}"],
                    cwd=str(repo_dir),
                    capture_output=True,
                    text=True,
                    timeout=30,
                    env=env,
                )
                if result.returncode == 0 and result.stdout.strip():
                    commit_hash = result.stdout.strip()
                    return (commit_hash, default_branch)
            except subprocess.CalledProcessError:
                pass

            # If date-based search failed, fall back to latest commit
            result = subprocess.run(
                ["git", "rev-parse", f"origin/{default_branch}"],
                cwd=str(repo_dir),
                capture_output=True,
                text=True,
                timeout=30,
                env=env,
            )
            if result.returncode == 0 and result.stdout.strip():
                commit_hash = result.stdout.strip()
                return (commit_hash, default_branch)
        else:
            # Use latest commit from ls-remote (no need to clone)
            result = subprocess.run(
                ["git", "ls-remote", vcs_url, f"refs/heads/{default_branch}"],
                capture_output=True,
                text=True,
                timeout=30,
                env=env,
            )
            if result.returncode == 0 and result.stdout:
                commit_hash = result.stdout.split()[0]
                return (commit_hash, default_branch)
    except Exception as e:
        print(f"  ⚠️  Fallback commit search failed: {e}")

    return None


def verify_commit_accessible(vcs_url: str, commit: str, ref_hint: str = "", version: str = "", timestamp: str = "") -> bool:
    """
    Fetch commit into a bare cache to ensure it exists upstream.

    Check cache age and force re-verification if too old.
    If commit doesn't exist, use fallback (latest commit on default branch or near timestamp)

    Args:
        vcs_url: Git repository URL
        commit: Commit hash to verify
        ref_hint: Optional ref (tag/branch) that should contain the commit
        version: Module version (for extracting timestamp from pseudo-versions)
        timestamp: ISO timestamp from .info file (for finding commits near that date)
    """
    from datetime import datetime, timezone, timedelta

    # Check cache before acquiring lock (fast path for already-verified commits)
    key = (vcs_url, commit)
    if key in VERIFY_RESULTS:
        return VERIFY_RESULTS[key]

    cache_key = f"{vcs_url}|||{commit}"

    # Track if verification passed via cache (to skip re-saving later)
    cached_verification_passed = False

    # Check cache with aging logic
    if cache_key in VERIFY_COMMIT_CACHE_V2:
        cache_entry = VERIFY_COMMIT_CACHE_V2[cache_key]
        if cache_entry.get("verified"):
            # Check if cache is too old
            last_checked_str = cache_entry.get("last_checked")
            if last_checked_str:
                try:
                    last_checked = datetime.fromisoformat(last_checked_str.replace('Z', '+00:00'))
                    age_days = (datetime.now(timezone.utc) - last_checked).days

                    if age_days < VERIFY_CACHE_MAX_AGE_DAYS:
                        # Cache is fresh for commit existence, but we still need branch detection
                        # Branch detection is cheap (local operation) and critical for BitBake recipes
                        # Don't return early - continue to branch detection below
                        cached_verification_passed = True
                    else:
                        # Cache is stale, force re-verification
                        print(f"  ⏰ Cache stale ({age_days} days old), re-verifying {commit[:12]}...")
                        # Fall through to re-verify
                except Exception:
                    # Can't parse timestamp, force re-verification
                    pass
            else:
                # No timestamp, but still need branch detection
                cached_verification_passed = True

    # Legacy cache format fallback
    if cache_key in VERIFY_COMMIT_CACHE and VERIFY_COMMIT_CACHE[cache_key]:
        # Migrate to v2 format during this check
        now = datetime.now(timezone.utc).isoformat()
        VERIFY_COMMIT_CACHE_V2[cache_key] = {
            "verified": True,
            "first_verified": now,
            "last_checked": now,
            "fetch_method": "cached"
        }
        # Don't return early - continue to branch detection
        cached_verification_passed = True

    # Ensure repo is initialized (this creates the lock too)
    repo_dir = _verify_repo_dir(vcs_url)

    # Now safely get the lock (guaranteed to exist after _verify_repo_dir returns)
    lock = VERIFY_REPO_LOCKS[vcs_url]

    with lock:
        # Double-check cache after acquiring lock (another thread may have verified while we waited)
        if key in VERIFY_RESULTS:
            return VERIFY_RESULTS[key]

        env = os.environ.copy()
        env.setdefault("GIT_TERMINAL_PROMPT", "0")
        env.setdefault("GIT_ASKPASS", "true")

        def _commit_exists(check_commit: str = None) -> bool:
            """Check if a commit exists in the local repo."""
            target = check_commit if check_commit else commit
            try:
                subprocess.run(
                    ["git", "rev-parse", "--verify", f"{target}^{{commit}}"],
                    cwd=str(repo_dir),
                    check=True,
                    capture_output=True,
                    env=env,
                )
                return True
            except subprocess.CalledProcessError:
                return False

        global VERIFY_COMMIT_CACHE_DIRTY, VERIFY_FALLBACK_COMMITS
        cached = VERIFY_COMMIT_CACHE.get(cache_key)

        commit_present = _commit_exists()
        if cached and not commit_present:
            # Cached entry without a local commit indicates stale data; drop it.
            VERIFY_COMMIT_CACHE.pop(cache_key, None)
            VERIFY_COMMIT_CACHE_DIRTY = True
            cached = None

        # Only do shallow fetch if commit is not already present
        # Doing --depth=1 on an already-full repo causes git to re-process history (very slow on large repos)
        if not commit_present and ref_hint:
            fetch_args = ["git", "fetch", "--depth=1", "origin", ref_hint]

            try:
                subprocess.run(
                    fetch_args,
                    cwd=str(repo_dir),
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=GIT_CMD_TIMEOUT,
                    env=env,
                )
            except subprocess.TimeoutExpired:
                print(f"  ⚠️  git fetch timeout ({GIT_CMD_TIMEOUT}s) for {vcs_url} {ref_hint or ''}")
            except subprocess.CalledProcessError as exc:
                detail = (exc.stderr or exc.stdout or "").strip() if isinstance(exc.stderr, str) or isinstance(exc.stdout, str) else ""
                if detail:
                    print(f"  ⚠️  git fetch failed for {vcs_url} {ref_hint or ''}: {detail}")
                # Continue to attempt direct commit fetch

        # For pseudo-versions, we need to determine which branch contains the commit
        # Strategy depends on whether this is a tagged version or pseudo-version
        commit_fetched = commit_present  # If already present, no need to fetch

        # Only use shallow fetch for actual tags - pseudo-versions with branch refs need unshallow
        is_tag_ref = ref_hint and ref_hint.startswith('refs/tags/')

        if is_tag_ref and not commit_present:
            # Tagged version: try shallow fetch of the specific commit (only if not already present)
            try:
                fetch_cmd = ["git", "fetch", "--depth=1", "origin", commit]
                subprocess.run(
                    fetch_cmd,
                    cwd=str(repo_dir),
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=GIT_CMD_TIMEOUT,
                    env=env,
                )
                commit_fetched = True

            except subprocess.CalledProcessError as exc:
                detail = (exc.stderr or exc.stdout or "").strip() if isinstance(exc.stderr, str) or isinstance(exc.stdout, str) else ""
                if detail:
                    print(f"  ⚠️  git fetch failed for {vcs_url[:50]}...: {detail[:100]}")

                # If fetching commit failed for a tag, check if tag has moved
                if ref_hint and ref_hint.startswith('refs/tags/'):
                    print(f"  → Tag commit not fetchable, checking if tag moved...")
                    try:
                        # Try fetching the tag again to see what it currently points to
                        subprocess.run(
                            ["git", "fetch", "--depth=1", "origin", ref_hint],
                            cwd=str(repo_dir),
                            check=True,
                            capture_output=True,
                            text=True,
                            timeout=GIT_CMD_TIMEOUT,
                            env=env,
                        )

                        # Check what commit the tag now points to
                        result = subprocess.run(
                            ["git", "rev-parse", "FETCH_HEAD"],
                            cwd=str(repo_dir),
                            capture_output=True,
                            text=True,
                            timeout=30,
                            env=env,
                            check=True,
                        )
                        current_tag_commit = result.stdout.strip()

                        if current_tag_commit != commit:
                            print(f"  ✓ Tag moved detected:")
                            print(f"     Proxy gave us: {commit[:12]} (no longer exists)")
                            print(f"     Tag now points to: {current_tag_commit[:12]}")
                            print(f"     → Using current tag commit")

                            # Update module to use current commit
                            VERIFY_FALLBACK_COMMITS[(vcs_url, commit)] = current_tag_commit
                            return ('corrected', module_path, version, commit, current_tag_commit)
                    except subprocess.CalledProcessError:
                        # Can't fetch tag either - this is a real error
                        pass

                for lock_file in ["shallow.lock", "index.lock", "HEAD.lock"]:
                    lock_path = repo_dir / lock_file
                    if lock_path.exists():
                        try:
                            lock_path.unlink()
                        except Exception:
                            pass
                VERIFY_RESULTS[key] = False
                VERIFY_COMMIT_CACHE.pop(cache_key, None)
                VERIFY_COMMIT_CACHE_DIRTY = True
                return False
        else:
            # Pseudo-version: MUST do full clone to detect which branch contains commit
            # Shallow fetch is useless - we need history for git for-each-ref --contains

            # Check if we already fetched full history for this repo URL
            # This prevents redundant full-history fetches for repos with multiple module versions
            shallow_file = repo_dir / "shallow"
            is_shallow = shallow_file.exists()
            already_full = vcs_url in VERIFY_FULL_REPOS

            if is_shallow and not already_full:
                print(f"  → Fetching full history for branch detection...")
                try:
                    # Use --unshallow to convert shallow clone to full clone
                    subprocess.run(
                        ["git", "fetch", "--unshallow", "origin", "+refs/heads/*:refs/remotes/origin/*"],
                        cwd=str(repo_dir),
                        check=True,
                        capture_output=True,
                        text=True,
                        timeout=GIT_CMD_TIMEOUT * 5,
                        env=env,
                    )
                    commit_fetched = True
                    # Mark this repo as having full history
                    VERIFY_FULL_REPOS.add(vcs_url)
                except subprocess.TimeoutExpired:
                    print(f"  ⚠️  Full clone timeout for {vcs_url[:50]}...")
                    for lock_file in ["shallow.lock", "index.lock", "HEAD.lock"]:
                        lock_path = repo_dir / lock_file
                        if lock_path.exists():
                            try:
                                lock_path.unlink()
                            except Exception:
                                pass
                    VERIFY_RESULTS[key] = False
                    VERIFY_COMMIT_CACHE.pop(cache_key, None)
                    VERIFY_COMMIT_CACHE_DIRTY = True
                    return False
                except subprocess.CalledProcessError as exc:
                    detail = (exc.stderr or exc.stdout or "").strip() if isinstance(exc.stderr, str) or isinstance(exc.stdout, str) else ""
                    if detail:
                        print(f"  ⚠️  Full clone failed for {vcs_url[:50]}...: {detail[:100]}")
                    for lock_file in ["shallow.lock", "index.lock", "HEAD.lock"]:
                        lock_path = repo_dir / lock_file
                        if lock_path.exists():
                            try:
                                lock_path.unlink()
                            except Exception:
                                pass
                    VERIFY_RESULTS[key] = False
                    VERIFY_COMMIT_CACHE.pop(cache_key, None)
                    VERIFY_COMMIT_CACHE_DIRTY = True
                    return False
            else:
                # Already full - just fetch updates
                print(f"  → Fetching updates (repo already full)...")
                try:
                    subprocess.run(
                        ["git", "fetch", "origin", "+refs/heads/*:refs/remotes/origin/*"],
                        cwd=str(repo_dir),
                        check=True,
                        capture_output=True,
                        text=True,
                        timeout=GIT_CMD_TIMEOUT,
                        env=env,
                    )
                    commit_fetched = True
                except subprocess.TimeoutExpired:
                    print(f"  ⚠️  Full clone timeout for {vcs_url[:50]}...")
                    for lock_file in ["shallow.lock", "index.lock", "HEAD.lock"]:
                        lock_path = repo_dir / lock_file
                        if lock_path.exists():
                            try:
                                lock_path.unlink()
                            except Exception:
                                pass
                    VERIFY_RESULTS[key] = False
                    VERIFY_COMMIT_CACHE.pop(cache_key, None)
                    VERIFY_COMMIT_CACHE_DIRTY = True
                    return False
                except subprocess.CalledProcessError as exc:
                    detail = (exc.stderr or exc.stdout or "").strip() if isinstance(exc.stderr, str) or isinstance(exc.stdout, str) else ""
                    if detail:
                        print(f"  ⚠️  Full clone failed for {vcs_url[:50]}...: {detail[:100]}")
                    for lock_file in ["shallow.lock", "index.lock", "HEAD.lock"]:
                        lock_path = repo_dir / lock_file
                        if lock_path.exists():
                            try:
                                lock_path.unlink()
                            except Exception:
                                pass
                    VERIFY_RESULTS[key] = False
                    VERIFY_COMMIT_CACHE.pop(cache_key, None)
                    VERIFY_COMMIT_CACHE_DIRTY = True
                    return False

        # Use the original commit or fallback commit for verification
        actual_commit = commit

        if not _commit_exists():
            # Commit doesn't exist in repository - try fallback strategy
            # This handles orphaned commits from proxy.golang.org
            print(f"  ⚠️  Commit {commit[:12]} not found in repository {vcs_url[:50]}...")

            if not ref_hint:
                # Pseudo-version without a tag - use timestamp-based fallback
                print(f"  → Attempting fallback commit strategy for pseudo-version {version}")
                fallback_result = _find_fallback_commit(vcs_url, version, timestamp)

                if fallback_result:
                    fallback_commit, fallback_branch = fallback_result
                    print(f"  ⚠️  Using fallback: {fallback_commit[:12]} from branch '{fallback_branch}'")
                    print(f"      (Original commit {commit[:12]} from proxy.golang.org does not exist)")

                    # Update commit to use the fallback
                    actual_commit = fallback_commit

                    # Track the fallback mapping so callers can use the fallback commit
                    VERIFY_FALLBACK_COMMITS[(vcs_url, commit)] = fallback_commit

                    # Fetch the fallback commit (only unshallow if repo is still shallow)
                    shallow_file = repo_dir / "shallow"
                    is_shallow = shallow_file.exists()
                    try:
                        if is_shallow:
                            subprocess.run(
                                ["git", "fetch", "--unshallow", "origin", "+refs/heads/*:refs/remotes/origin/*"],
                                cwd=str(repo_dir),
                                check=True,
                                capture_output=True,
                                text=True,
                                timeout=GIT_CMD_TIMEOUT * 5,
                                env=env,
                            )
                        else:
                            # Repo already has full history - just fetch updates
                            subprocess.run(
                                ["git", "fetch", "origin", "+refs/heads/*:refs/remotes/origin/*"],
                                cwd=str(repo_dir),
                                check=True,
                                capture_output=True,
                                text=True,
                                timeout=GIT_CMD_TIMEOUT,
                                env=env,
                            )
                    except Exception as e:
                        print(f"  ⚠️  Failed to fetch fallback commit: {e}")
                        VERIFY_RESULTS[key] = False
                        return False

                    # Register the fallback branch
                    VERIFY_DETECTED_BRANCHES[(vcs_url, fallback_commit)] = fallback_branch

                    # Check if fallback commit exists
                    if not _commit_exists(fallback_commit):
                        print(f"  ⚠️  Fallback commit {fallback_commit[:12]} also not found!")
                        VERIFY_RESULTS[key] = False
                        return False
                else:
                    print(f"  ⚠️  Could not determine fallback commit")
                    VERIFY_RESULTS[key] = False
                    return False
            else:
                # Tagged version with bad commit - this shouldn't happen but fail gracefully
                print(f"  ⚠️  Tagged version {version} has invalid commit {commit[:12]}")
                VERIFY_RESULTS[key] = False
                return False

        # Now verify the actual_commit (original or fallback)
        if _commit_exists(actual_commit):
            # Commit was fetched successfully - verify it's reachable from the ref_hint if provided
            # This ensures the commit is on the branch/tag we'll use in SRC_URI
            if ref_hint:
                # For tagged versions, verify the tag still points to the same commit
                # proxy.golang.org caches module@version->commit mappings, but tags can be force-pushed
                # If the tag has moved to a different commit, we need to use the current commit
                # Optimization: Use git ls-remote first (fast, cached) before fetching
                if ref_hint.startswith('refs/tags/'):
                    try:
                        # First check if tag has moved using fast ls-remote (cached)
                        # FIX #37: Use dereferenced tag (^{}) to get the actual commit hash
                        # For annotated tags, ref_hint returns the tag object hash, not the commit
                        # Example: refs/tags/v1.0.1 -> c49ff274 (tag object)
                        #          refs/tags/v1.0.1^{} -> 37c8de36 (actual commit)
                        current_tag_commit = git_ls_remote(vcs_url, f"{ref_hint}^{{}}")

                        if current_tag_commit and current_tag_commit != actual_commit:
                            # Tag has moved - fetch it to verify and update local repo
                            print(f"  ⚠️  Tag has moved - proxy.golang.org cache is stale")
                            print(f"     Proxy gave us: {actual_commit[:12]}")
                            print(f"     Tag now points to: {current_tag_commit[:12]}")
                            print(f"     → Using current tag commit")

                            # Fetch the tag to update local repo
                            subprocess.run(
                                ["git", "fetch", "--depth=1", "origin", ref_hint],
                                cwd=str(repo_dir),
                                check=True,
                                capture_output=True,
                                text=True,
                                timeout=GIT_CMD_TIMEOUT,
                                env=env,
                            )

                            # Update to use current commit
                            VERIFY_FALLBACK_COMMITS[(vcs_url, actual_commit)] = current_tag_commit
                            actual_commit = current_tag_commit

                            # Verify the new commit exists (it should, since we just fetched it)
                            if not _commit_exists(current_tag_commit):
                                print(f"  ⚠️  Current tag commit {current_tag_commit[:12]} not found!")
                                VERIFY_RESULTS[key] = False
                                VERIFY_COMMIT_CACHE.pop(cache_key, None)
                                VERIFY_COMMIT_CACHE_DIRTY = True
                                return False

                            # The VERIFY_FALLBACK_COMMITS mapping will be used by the caller
                            # Continue with verification using the corrected commit
                    except Exception as e:
                        # Tag verification failed - continue with normal flow
                        print(f"  ⚠️  Could not verify tag target: {e}")
                        pass

                try:
                    # Check if commit is an ancestor of (or equal to) the ref
                    # This works even with shallow clones
                    result = subprocess.run(
                        ["git", "merge-base", "--is-ancestor", actual_commit, "FETCH_HEAD"],
                        cwd=str(repo_dir),
                        capture_output=True,
                        text=True,
                        timeout=30,
                        env=env,
                    )
                    if result.returncode != 0:
                        # Commit is not an ancestor of the ref - might be on a different branch
                        # This is OK - BitBake can still fetch the commit directly
                        # Just log it for debugging
                        pass  # Don't fail - commit exists and is fetchable
                except subprocess.TimeoutExpired:
                    print(f"  ⚠️  Timeout checking commit ancestry for {actual_commit[:12]}")
                    # Don't fail - commit exists
                except subprocess.CalledProcessError:
                    # merge-base failed - don't fail verification
                    pass
            else:
                # For pseudo-versions, we MUST detect which branch contains the commit
                # This is CRITICAL - BitBake cannot fetch arbitrary commits with nobranch=1
                # We need branch=<name> in SRC_URI for interior commits

                # Check if we already have the branch from fallback
                if (vcs_url, actual_commit) not in VERIFY_DETECTED_BRANCHES:
                    # Now that we have full history, use git to find which branches contain this commit
                    try:
                        result = subprocess.run(
                            ["git", "for-each-ref", "--contains", actual_commit, "refs/remotes/origin/", "--format=%(refname:short)"],
                            cwd=str(repo_dir),
                            capture_output=True,
                            text=True,
                            timeout=30,
                            env=env,
                        )
                        if result.returncode == 0 and result.stdout.strip():
                            # Commit IS on one or more branches
                            branches = result.stdout.strip().split('\n')
                            # Strip 'origin/' prefix from branch names
                            branches = [b.replace('origin/', '') for b in branches]

                            # Pick main/master if available, otherwise first branch
                            if 'main' in branches:
                                detected_branch = 'main'
                            elif 'master' in branches:
                                detected_branch = 'master'
                            else:
                                detected_branch = branches[0]

                            VERIFY_DETECTED_BRANCHES[(vcs_url, actual_commit)] = detected_branch
                            print(f"  → Detected branch: {detected_branch} (verified with git for-each-ref)")
                        else:
                            # Commit exists but not in any branch - it's orphaned/dangling
                            # For pseudo-versions, try fallback strategy
                            # DEBUG: ALWAYS print this to confirm we reach this block
                            print(f"  ⚠️  ORPHANED: Commit {actual_commit[:12]} not found in any branch for {vcs_url[:50]}")
                            print(f"  DEBUG-ORPHANED: ref_hint={ref_hint}, actual_commit={actual_commit[:12]}, commit={commit[:12]}, version={version}")
                            print(f"  DEBUG-ORPHANED: Condition: (not ref_hint)={not ref_hint}, (actual==commit)={actual_commit == commit}")

                            if not ref_hint and actual_commit == commit:
                                # This is a pseudo-version with orphaned commit - try fallback
                                print(f"  → Attempting fallback commit strategy for orphaned commit")
                                fallback_result = _find_fallback_commit(vcs_url, version, timestamp)

                                if fallback_result:
                                    fallback_commit, fallback_branch = fallback_result
                                    print(f"  ✓ Using fallback: {fallback_commit[:12]} from branch '{fallback_branch}'")
                                    print(f"    (Original commit {commit[:12]} from proxy.golang.org is orphaned)")

                                    # Update to use the fallback
                                    actual_commit = fallback_commit
                                    VERIFY_FALLBACK_COMMITS[(vcs_url, commit)] = fallback_commit
                                    VERIFY_DETECTED_BRANCHES[(vcs_url, fallback_commit)] = fallback_branch

                                    # Verify fallback commit exists
                                    if not _commit_exists(fallback_commit):
                                        print(f"  ⚠️  Fallback commit {fallback_commit[:12]} not found!")
                                        VERIFY_RESULTS[key] = False
                                        return False
                                    # Continue with fallback commit - don't fail here
                                else:
                                    print(f"  ⚠️  Could not determine fallback commit")
                                    VERIFY_RESULTS[key] = False
                                    return False
                            else:
                                # Tagged version or already tried fallback - fail
                                VERIFY_RESULTS[key] = False
                                return False
                    except subprocess.TimeoutExpired:
                        print(f"  ⚠️  Branch detection timeout for {actual_commit[:12]}")
                        VERIFY_RESULTS[key] = False
                        return False
                    except subprocess.CalledProcessError:
                        print(f"  ⚠️  Failed to detect branch for {actual_commit[:12]}")
                        VERIFY_RESULTS[key] = False
                        return False


            # Commit exists AND is reachable - safe for BitBake nobranch=1
            # Only save to cache if not already cached (branch detection is done, just finalize)
            if not cached_verification_passed:
                # Save with timestamp in v2 format
                now = datetime.now(timezone.utc).isoformat()
                existing_entry = VERIFY_COMMIT_CACHE_V2.get(cache_key, {})

                VERIFY_COMMIT_CACHE_V2[cache_key] = {
                    "verified": True,
                    "first_verified": existing_entry.get("first_verified", now),
                    "last_checked": now,
                    "fetch_method": "fetch"  # Successfully fetched from upstream
                }
                VERIFY_COMMIT_CACHE_DIRTY = True

            VERIFY_RESULTS[key] = True
            return True
        VERIFY_RESULTS[key] = False
        # Remove from both caches
        VERIFY_COMMIT_CACHE.pop(cache_key, None)
        VERIFY_COMMIT_CACHE_V2.pop(cache_key, None)
        VERIFY_COMMIT_CACHE_DIRTY = True
        return False


def get_actual_commit(vcs_url: str, commit: str) -> str:
    """
    Get the actual commit to use, applying fallback if original commit doesn't exist.

    This should be called after verify_commit_accessible() to get the commit that was
    actually verified (which may be a fallback if the original didn't exist).

    Args:
        vcs_url: Repository URL
        commit: Original commit hash from proxy.golang.org

    Returns:
        Fallback commit if one was used, otherwise the original commit
    """
    return VERIFY_FALLBACK_COMMITS.get((vcs_url, commit), commit)


def _ref_points_to_commit(vcs_url: str, ref_hint: str, commit_hash: str) -> bool:
    if not ref_hint:
        return False

    repo_dir = _verify_repo_dir(vcs_url)
    # Lock is guaranteed to exist after _verify_repo_dir returns
    lock = VERIFY_REPO_LOCKS[vcs_url]

    with lock:
        env = os.environ.copy()
        env.setdefault("GIT_TERMINAL_PROMPT", "0")
        env.setdefault("GIT_ASKPASS", "true")

        try:
            result = subprocess.run(
                ["git", "show-ref", "--verify", "--hash", ref_hint],
                cwd=str(repo_dir),
                check=True,
                capture_output=True,
                text=True,
                env=env,
            )
            resolved = result.stdout.strip().lower()
            return resolved == commit_hash.lower()
        except subprocess.CalledProcessError:
            return False


def correct_commit_hash_from_ref(vcs_url: str, vcs_hash: str, vcs_ref: str) -> Optional[str]:
    """
    Fix proxy.golang.org bad hashes by dereferencing the tag to get the correct commit.

    proxy.golang.org sometimes returns commits that:
    1. Exist in the repo but aren't branch/tag HEADs (dangling commits)
    2. Don't exist in the repo at all

    BitBake's nobranch=1 requires commits to be HEADs of branches or dereferenced tags.

    Args:
        vcs_url: Repository URL
        vcs_hash: Commit hash from proxy.golang.org (potentially bad)
        vcs_ref: Git ref like "refs/tags/v1.2.3"

    Returns:
        Corrected commit hash if different from vcs_hash, None if vcs_hash is correct or can't be corrected
    """
    if not vcs_ref or not vcs_ref.startswith("refs/"):
        return None

    # Try dereferenced tag first (annotated tags)
    dereferenced_hash = git_ls_remote(vcs_url, f"{vcs_ref}^{{}}")
    if dereferenced_hash and dereferenced_hash.lower() != vcs_hash.lower():
        return dereferenced_hash.lower()

    # Try without ^{} for lightweight tags
    commit_hash = git_ls_remote(vcs_url, vcs_ref)
    if commit_hash and commit_hash.lower() != vcs_hash.lower():
        return commit_hash.lower()

    return None


def is_commit_bitbake_fetchable(vcs_url: str, vcs_hash: str, vcs_ref: str) -> bool:
    """
    Check if a commit is BitBake-fetchable (is a branch/tag HEAD).

    BitBake's nobranch=1 requires commits to be:
    - HEAD of a branch (refs/heads/*)
    - HEAD of a dereferenced tag (refs/tags/*^{})

    Uses cached git ls-remote to check if the commit appears in the remote repository as a ref HEAD.

    Args:
        vcs_url: Repository URL
        vcs_hash: Commit hash to check
        vcs_ref: Git ref hint like "refs/tags/v1.2.3"

    Returns:
        True if commit is a branch/tag HEAD, False if dangling/not found
    """
    # Quick check: Does the ref point to this commit?
    if vcs_ref and vcs_ref.startswith("refs/"):
        # Try dereferenced tag (annotated)
        ref_commit = git_ls_remote(vcs_url, f"{vcs_ref}^{{}}")
        if ref_commit and ref_commit.lower() == vcs_hash.lower():
            return True

        # Try without ^{} for lightweight tags
        ref_commit = git_ls_remote(vcs_url, vcs_ref)
        if ref_commit and ref_commit.lower() == vcs_hash.lower():
            return True

    # If we get here, the vcs_hash doesn't match the ref, so it's dangling
    return False


def verify_gomodcache_commits(gomodcache_path: Path, verify_jobs: int = 10) -> int:
    """
    Verify commits in GOMODCACHE .info files still exist in repositories.

    Detects force-pushed tags where proxy.golang.org has stale commit hashes.
    Offers to automatically refresh stale .info files by re-downloading.

    Returns:
        0 if all commits valid or successfully refreshed
        1 if stale commits found and user declined refresh
    """
    global VERIFY_ENABLED
    VERIFY_ENABLED = True

    if isinstance(gomodcache_path, str):
        gomodcache_path = Path(gomodcache_path)

    if not gomodcache_path.exists():
        print(f"❌ GOMODCACHE not found: {gomodcache_path}")
        return 1

    download_dir = gomodcache_path / "cache" / "download"
    if not download_dir.exists():
        print(f"❌ Download directory not found: {download_dir}")
        return 1

    print(f"\nScanning {download_dir} for .info files...")

    # Collect all modules with VCS info
    modules_to_check = []
    for dirpath, _, filenames in os.walk(download_dir):
        path_parts = Path(dirpath).relative_to(download_dir).parts
        if not path_parts or path_parts[-1] != '@v':
            continue

        module_path = '/'.join(path_parts[:-1])
        module_path = unescape_module_path(module_path)

        for filename in filenames:
            if not filename.endswith('.info'):
                continue

            version = filename[:-5]
            info_path = Path(dirpath) / filename

            try:
                with open(info_path) as f:
                    info = json.load(f)

                origin = info.get('Origin', {})
                vcs_url = origin.get('URL')
                vcs_hash = origin.get('Hash')
                vcs_ref = origin.get('Ref', '')

                if vcs_url and vcs_hash and len(vcs_hash) == 40:
                    modules_to_check.append({
                        'module_path': module_path,
                        'version': version,
                        'vcs_url': vcs_url,
                        'vcs_hash': vcs_hash,
                        'vcs_ref': vcs_ref,
                        'info_path': info_path
                    })
            except Exception as e:
                print(f"  ⚠️  Error reading {info_path}: {e}")

    print(f"Found {len(modules_to_check)} modules with VCS metadata to verify\n")

    if not modules_to_check:
        print("✅ No modules to verify")
        return 0

    # Verify commits in parallel
    stale_modules = []

    def check_module(module):
        if verify_commit_accessible(module['vcs_url'], module['vcs_hash'], module['vcs_ref'], module.get('version', '')):
            return None
        else:
            return module

    if verify_jobs > 0:
        print(f"Verifying commits in parallel ({verify_jobs} workers)...")
        with ThreadPoolExecutor(max_workers=verify_jobs) as executor:
            futures = {executor.submit(check_module, m): m for m in modules_to_check}
            for future in futures:
                result = future.result()
                if result:
                    stale_modules.append(result)
    else:
        print("Verifying commits sequentially...")
        for module in modules_to_check:
            result = check_module(module)
            if result:
                stale_modules.append(result)

    if not stale_modules:
        print(f"\n✅ All {len(modules_to_check)} commits verified successfully!")
        return 0

    # Report stale modules
    print(f"\n⚠️  Found {len(stale_modules)} modules with STALE commits:\n")
    for module in stale_modules[:10]:  # Show first 10
        print(f"  {module['module_path']}@{module['version']}")
        print(f"    Commit: {module['vcs_hash'][:12]} (not found in {module['vcs_url']})")
        print(f"    File: {module['info_path']}")
        print()

    if len(stale_modules) > 10:
        print(f"  ... and {len(stale_modules) - 10} more\n")

    # Offer to auto-refresh
    print("These commits likely represent force-pushed tags.")
    print("The .info files can be refreshed by re-downloading from proxy.golang.org\n")

    response = input("Refresh stale .info files automatically? [y/N]: ").strip().lower()
    if response not in ('y', 'yes'):
        print("\nNo action taken. To fix manually:")
        print("  1. Delete stale .info files")
        print("  2. Run: go mod download")
        return 1

    # Refresh stale modules
    print("\nRefreshing stale modules...")
    refreshed = 0
    failed = []

    for module in stale_modules:
        print(f"\n  Refreshing {module['module_path']}@{module['version']}...")

        try:
            # Delete stale .info file
            module['info_path'].unlink()
            print(f"    Deleted stale .info")

            # Re-download
            result = subprocess.run(
                ['go', 'mod', 'download', f"{module['module_path']}@{module['version']}"],
                capture_output=True,
                text=True,
                timeout=60
            )

            if result.returncode == 0 and module['info_path'].exists():
                # Verify new commit
                with open(module['info_path']) as f:
                    new_info = json.load(f)
                new_hash = new_info.get('Origin', {}).get('Hash', '')

                if new_hash and new_hash != module['vcs_hash']:
                    print(f"    ✓ Refreshed: {module['vcs_hash'][:12]} → {new_hash[:12]}")
                    refreshed += 1
                else:
                    print(f"    ⚠️  Proxy returned same commit")
                    failed.append(module)
            else:
                print(f"    ❌ Download failed: {result.stderr[:100]}")
                failed.append(module)
        except Exception as e:
            print(f"    ❌ Error: {e}")
            failed.append(module)

    print(f"\n{'='*70}")
    print(f"Refresh complete: {refreshed} refreshed, {len(failed)} failed")

    if failed:
        print(f"\nFailed modules require manual intervention:")
        for module in failed[:5]:
            print(f"  {module['module_path']}@{module['version']}")
        return 1

    return 0


def is_module_actually_needed(module_path: str, source_dir: Path) -> bool:
    """
    Check if a module is actually used by running 'go mod why'.

    Returns:
        True if module is needed by the main module
        False if module is indirect-only and not actually imported
    """
    try:
        result = subprocess.run(
            ['go', 'mod', 'why', module_path],
            cwd=str(source_dir),
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode != 0:
            # If go mod why fails, assume it's needed (conservative)
            return True

        output = result.stdout.strip()

        # Check for the telltale sign that module is not needed
        if "(main module does not need package" in output:
            return False

        # Also check for completely empty output (module not in graph)
        if not output or output == f"# {module_path}":
            return False

        # Module is needed
        return True

    except Exception:
        # On error, assume needed (conservative)
        return True


def _execute(args: argparse.Namespace) -> int:
    global CURRENT_SOURCE_DIR, CURRENT_GOMODCACHE, VERIFY_COMMIT_CACHE_DIRTY
    debug_limit = args.debug_limit

    if args.source_dir:
        source_dir = Path(args.source_dir).resolve()
    else:
        source_dir = Path.cwd()
    CURRENT_SOURCE_DIR = source_dir

    if not (source_dir / "go.mod").exists():
        print(f"❌ Error: go.mod not found in {source_dir}")
        return 1

    print(f"Source directory: {source_dir}")

    if args.recipedir:
        output_dir = Path(args.recipedir).resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
        print(f"Output directory: {output_dir}")
    else:
        output_dir = None
        if not args.validate and not args.dry_run:
            print("❌ Error: --recipedir is required unless running with --validate, --dry-run, or cache-maintenance flags.")
            return 1

    configure_cache_paths(args.cache_dir, args.clone_cache_dir)
    if args.cache_dir:
        print(f"Metadata cache directory: {CACHE_BASE_DIR}")
    if args.clone_cache_dir:
        print(f"Clone cache directory: {CLONE_CACHE_DIR}")

    # Set verification cache max age from command line
    global MODULE_REPO_OVERRIDES_DIRTY, VERIFY_CACHE_MAX_AGE_DAYS
    VERIFY_CACHE_MAX_AGE_DAYS = args.verify_cache_max_age
    if VERIFY_CACHE_MAX_AGE_DAYS == 0:
        print(f"Verification cache: DISABLED (always verify)")
    else:
        print(f"Verification cache max age: {VERIFY_CACHE_MAX_AGE_DAYS} days")

    if args.clear_repo:
        for (module_spec,) in args.clear_repo:
            module_path, version = _parse_override_spec(module_spec)
            removed = False
            try:
                key = _normalise_override_key(module_path, version)
            except ValueError as exc:
                print(f"Invalid module override '{module_spec}': {exc}")
                continue
            if version is not None:
                if MODULE_REPO_OVERRIDES.pop(key, None) is not None:
                    removed = True
                    MODULE_REPO_OVERRIDES_DIRTY = True
                    print(f"Cleared repo override: {module_path}@{version}")
            else:
                wildcard_key = key
                if MODULE_REPO_OVERRIDES.pop(wildcard_key, None) is not None:
                    removed = True
                specific_keys = [
                    candidate for candidate in list(MODULE_REPO_OVERRIDES.keys())
                    if candidate[0] == module_path and candidate[1] is not None
                ]
                for candidate in specific_keys:
                    MODULE_REPO_OVERRIDES.pop(candidate, None)
                    removed = True
                if removed:
                    MODULE_REPO_OVERRIDES_DIRTY = True
                    print(f"Cleared repo overrides for: {module_path}")
            if not removed:
                if version is not None:
                    print(f"No repo override found for: {module_path}@{version}")
                else:
                    print(f"No repo overrides found for: {module_path}")

    if args.set_repo:
        for module_spec, repo_url in args.set_repo:
            module_path, version = _parse_override_spec(module_spec)
            try:
                key = _normalise_override_key(module_path, version)
            except ValueError as exc:
                print(f"Invalid module override '{module_spec}': {exc}")
                continue
            MODULE_REPO_OVERRIDES[key] = repo_url
            MODULE_REPO_OVERRIDES_DIRTY = True
            label = f"{module_path}@{version}" if version else module_path
            print(f"Pinned repo override: {label} -> {repo_url}")

    if args.clear_commit:
        for repo, commit in args.clear_commit:
            key = f"{repo}|||{commit}"
            if key in VERIFY_COMMIT_CACHE:
                VERIFY_COMMIT_CACHE.pop(key, None)
                VERIFY_COMMIT_CACHE_DIRTY = True
                print(f"\n🧹 Cleared cached verification: {repo} {commit}\n")
            else:
                print(f"No cached verification found for: {repo} {commit}")
            VERIFY_RESULTS.pop((repo, commit), None)

    if args.inject_commit:
        for repo, commit in args.inject_commit:
            key = f"{repo}|||{commit}"
            VERIFY_COMMIT_CACHE[key] = True
            VERIFY_COMMIT_CACHE_DIRTY = True
            VERIFY_RESULTS[(repo, commit)] = True
            print(f"Injected verified commit: {repo} {commit}")

    exit_code = 0

    if args.clean_ls_remote_cache:
        print("\n🗑️  Cleaning git ls-remote cache...")
        if LS_REMOTE_CACHE_PATH.exists():
            LS_REMOTE_CACHE_PATH.unlink()
            print(f"   Removed {LS_REMOTE_CACHE_PATH}")
        else:
            print(f"   Cache file not found: {LS_REMOTE_CACHE_PATH}")
        args.clean_cache = True

    if args.clean_cache:
        print("\n🗑️  Cleaning module metadata cache...")
        if MODULE_METADATA_CACHE_PATH.exists():
            MODULE_METADATA_CACHE_PATH.unlink()
            print(f"   Removed {MODULE_METADATA_CACHE_PATH}")
        else:
            print(f"   Cache file not found: {MODULE_METADATA_CACHE_PATH}")
        if VERIFY_COMMIT_CACHE_PATH.exists():
            VERIFY_COMMIT_CACHE_PATH.unlink()
            print(f"   Removed {VERIFY_COMMIT_CACHE_PATH}")
        VERIFY_COMMIT_CACHE.clear()
        VERIFY_COMMIT_CACHE_DIRTY = False
        print("   Note: Bootstrap from .inc files DISABLED to avoid reloading stale data.")
        skip_inc_files = True
    else:
        skip_inc_files = False

    skip_legacy_module_cache = args.skip_legacy_module_cache
    bootstrap_metadata_cache(
        output_dir,
        skip_inc_files=skip_inc_files,
        skip_legacy_module_cache=skip_legacy_module_cache,
    )
    prune_metadata_cache()
    load_ls_remote_cache()
    load_vanity_url_cache()

    if args.dry_run:
        print("\n--dry-run requested; skipping discovery/validation")
        return 0

    # --verify-cached command to check GOMODCACHE for stale commits
    if args.verify_cached:
        print("\n" + "=" * 70)
        print("VERIFYING CACHED COMMITS IN GOMODCACHE")
        print("=" * 70)
        return verify_gomodcache_commits(args.gomodcache or source_dir / ".gomodcache", args.verify_jobs)

    # Check for --discovered-modules (bootstrap strategy)
    if args.discovered_modules:
        print("\n" + "=" * 70)
        print("PRE-DISCOVERED MODULES MODE")
        print("=" * 70)
        print("\nUsing pre-discovered module metadata from BitBake discovery build")
        print("Skipping discovery phase - generator will convert to BitBake format\n")

        discovered_modules_path = Path(args.discovered_modules).resolve()
        modules = load_discovered_modules(discovered_modules_path)

        if modules is None:
            print("\n❌ Failed to load discovered modules - falling back to discovery")
            modules = discover_modules(source_dir, args.gomodcache)
        else:
            print(f"\n✓ Successfully loaded {len(modules)} modules from discovery metadata")
            print("  Skipping 'go mod download' discovery phase")
            print("  Will use go.sum to resolve modules without Origin metadata")

            # Auto-correction of dangling commits happens in Phase 2 during parallel verification
    else:
        # Normal discovery path
        modules = discover_modules(source_dir, args.gomodcache)
    if debug_limit is not None and len(modules) > debug_limit:
        print(f"\n⚙️  Debug limit active: truncating discovered modules to first {debug_limit} entries")
        modules = modules[:debug_limit]

    # Set VERIFY_ENABLED based on whether verification is requested
    global VERIFY_ENABLED
    VERIFY_ENABLED = not args.skip_verify

    # Parse go.mod replace directives for fork resolution
    # Example: github.com/containerd/containerd/v2 => github.com/k3s-io/containerd/v2 v2.1.4-k3s2
    go_mod_replaces = parse_go_mod_replaces(source_dir / "go.mod")
    if go_mod_replaces:
        print(f"\n✓ Parsed {len(go_mod_replaces)} replace directives from go.mod")
        if VERBOSE_MODE:
            for old_path, (new_path, new_version) in sorted(go_mod_replaces.items())[:5]:
                print(f"  {old_path} => {new_path} {new_version}")
            if len(go_mod_replaces) > 5:
                print(f"  ... and {len(go_mod_replaces) - 5} more")

    # Parse go.sum for fallback resolution
    discovered_keys = {(m['module_path'], m['version']) for m in modules}
    go_sum_modules_with_source, go_sum_indirect_only = parse_go_sum(source_dir / "go.sum")

    FAILED_MODULE_PATHS.clear()
    FAILED_MODULE_ENTRIES.clear()
    SKIPPED_MODULES.clear()

    print(f"\nFound {len(go_sum_indirect_only)} indirect-only dependencies (skipping - only need .mod files)")

    if args.discovered_modules:
        # With discovered modules, only resolve what's in go.sum but missing from discovery
        # Do NOT call go list -m all - we already know what we need from the successful build
        missing_from_discovery = go_sum_modules_with_source - discovered_keys
        print(f"Discovered modules provided {len(discovered_keys)} modules with Origin metadata")
        print(f"go.sum has {len(go_sum_modules_with_source)} modules total")
        print(f"Resolving {len(missing_from_discovery)} modules without Origin metadata...")
    else:
        # Normal discovery - also use go list to find additional modules
        go_list_modules = collect_modules_via_go_list(source_dir)
        go_sum_modules_with_source |= go_list_modules
        missing_from_discovery = go_sum_modules_with_source - discovered_keys
        print(f"Resolving {len(missing_from_discovery)} additional modules discovered from go.sum/go list...")

    modules_by_path: Dict[str, List[Dict]] = {}
    for m in modules:
        modules_by_path.setdefault(m['module_path'], []).append(m)

    limit_reached = False
    for module_path, version in sorted(go_sum_modules_with_source):
        if debug_limit is not None and len(modules) >= debug_limit:
            limit_reached = True
            break
        if module_path in FAILED_MODULE_PATHS:
            print(f"  ⚠️  Skipping {module_path}@{version} (previous resolution failure)")
            continue

        if (module_path, version) in discovered_keys:
            continue

        # Apply replace directives for k3s forks
        # If module path is replaced in go.mod, try to resolve using the replacement path
        resolved_path = module_path
        resolved_version = version
        if module_path in go_mod_replaces:
            new_path, new_version = go_mod_replaces[module_path]
            if new_version:  # Replace has explicit version
                resolved_path = new_path
                resolved_version = new_version
                if VERBOSE_MODE:
                    print(f"  [replace] {module_path}@{version} => {resolved_path}@{resolved_version}")
                # Check if we already have the replacement module
                if (resolved_path, resolved_version) in discovered_keys:
                    # Copy the existing module entry with original path
                    for m in modules:
                        if m['module_path'] == resolved_path and m['version'] == resolved_version:
                            replacement_entry = m.copy()
                            replacement_entry['module_path'] = module_path
                            replacement_entry['version'] = version
                            modules.append(replacement_entry)
                            discovered_keys.add((module_path, version))
                            modules_by_path.setdefault(module_path, []).append(replacement_entry)
                            print(f"  ✓ {module_path}@{version} (using replace directive -> {resolved_path}@{resolved_version})")
                            continue

        fallback = resolve_module_metadata(resolved_path, resolved_version)
        if fallback:
            # If we used a replace directive, update the entry to use the original path
            if resolved_path != module_path or resolved_version != version:
                fallback['module_path'] = module_path
                fallback['version'] = version
                print(f"  ✓ {module_path}@{version} (resolved via replace -> {resolved_path}@{resolved_version})")
            modules.append(fallback)
            discovered_keys.add((module_path, version))
            modules_by_path.setdefault(module_path, []).append(fallback)
            if debug_limit is not None and len(modules) >= debug_limit:
                limit_reached = True
                break
        else:
            # Handle monorepo submodule replacements (e.g., github.com/k3s-io/etcd/server/v3)
            # When a replacement points to a submodule path that doesn't have its own VCS entry,
            # try to find the base repository and use it with a subdir.
            # Example: github.com/k3s-io/etcd/server/v3 -> base: github.com/k3s-io/etcd, subdir: server/v3
            monorepo_handled = False
            if resolved_path != module_path and '/' in resolved_path:
                # Check if this looks like a submodule path (has version suffix like /v2, /v3, etc.)
                parts = resolved_path.rsplit('/', 1)
                if len(parts) == 2:
                    potential_base = parts[0]
                    potential_subdir = parts[1]

                    # Look for version-suffixed paths (e.g., /v2, /v3, /server/v3, /client/v3)
                    # Try progressively shorter base paths
                    base_candidates = []
                    path_segments = resolved_path.split('/')

                    # For github.com/k3s-io/etcd/server/v3:
                    # Try: github.com/k3s-io/etcd/server, github.com/k3s-io/etcd
                    for i in range(len(path_segments) - 1, 2, -1):  # At least keep domain + org
                        candidate_base = '/'.join(path_segments[:i])
                        candidate_subdir = '/'.join(path_segments[i:])
                        base_candidates.append((candidate_base, candidate_subdir))

                    # Try each candidate base path
                    for base_path, subdir in base_candidates:
                        if base_path in modules_by_path:
                            # Found the base repository! Create a submodule entry
                            base_module = modules_by_path[base_path][0]
                            vcs_url = base_module['vcs_url']

                            # Use the replacement version for the tag
                            tag = resolved_version.split('+')[0]
                            commit = git_ls_remote(vcs_url, f"refs/tags/{tag}") or git_ls_remote(vcs_url, tag)

                            if commit:
                                timestamp = derive_timestamp_from_version(resolved_version)
                                fallback = {
                                    "module_path": module_path,  # Original path (go.etcd.io/etcd/server/v3)
                                    "version": version,
                                    "vcs_url": vcs_url,
                                    "vcs_hash": commit,
                                    "vcs_ref": f"refs/tags/{tag}" if git_ls_remote(vcs_url, f"refs/tags/{tag}") else tag,
                                    "timestamp": timestamp,
                                    "subdir": subdir,  # e.g., "server/v3"
                                }
                                modules.append(fallback)
                                discovered_keys.add((module_path, version))
                                modules_by_path.setdefault(module_path, []).append(fallback)
                                print(f"  ✓ {module_path}@{version} (monorepo submodule: base={base_path}, subdir={subdir})")
                                monorepo_handled = True
                                if debug_limit is not None and len(modules) >= debug_limit:
                                    limit_reached = True
                                break

                    if monorepo_handled:
                        if limit_reached:
                            break
                        continue

            if module_path in modules_by_path:
                reference_module = modules_by_path[module_path][0]
                vcs_url = reference_module['vcs_url']
                tag = version.split('+')[0]
                commit = None
                pseudo_info = parse_pseudo_version_tag(tag)

                if pseudo_info:
                    timestamp_str, short_commit = pseudo_info
                    commit = resolve_pseudo_version_commit(
                        vcs_url,
                        timestamp_str,
                        short_commit,
                        clone_cache_dir=CLONE_CACHE_DIR
                    )
                    if commit:
                        print(f"  ✓ {module_path}@{version} (resolved pseudo-version via repository clone)")
                else:
                    commit = git_ls_remote(vcs_url, f"refs/tags/{tag}") or git_ls_remote(vcs_url, tag)
                    if commit:
                        print(f"  ✓ {module_path}@{version} (resolved using VCS URL from sibling version)")

                if commit:
                    timestamp = derive_timestamp_from_version(version)
                    subdir = reference_module.get('subdir', '')
                    update_metadata_cache(module_path, version, vcs_url, commit, timestamp, subdir, '', dirty=True)
                    fallback = {
                        "module_path": module_path,
                        "version": version,
                        "vcs_url": vcs_url,
                        "vcs_hash": commit,
                        "vcs_ref": "",
                        "timestamp": timestamp,
                        "subdir": subdir,
                    }
                    modules.append(fallback)
                    discovered_keys.add((module_path, version))
                    modules_by_path[module_path].append(fallback)
                    if debug_limit is not None and len(modules) >= debug_limit:
                        limit_reached = True
                        break
                    continue

            # Skip monorepo root modules that fail resolution when we have submodules
            # Example: go.etcd.io/etcd/v3 (root) when we have github.com/k3s-io/etcd/server/v3, etc.
            # Handles both direct prefix match and forked monorepos (via VCS URL comparison)
            # These are never actually imported - they just exist in go.sum due to the monorepo go.mod
            is_monorepo_root = False

            # Check 1: Direct prefix match (same repository, e.g., go.etcd.io/etcd/v3 → go.etcd.io/etcd/server/v3)
            if any(existing_path.startswith(module_path + '/') for existing_path in modules_by_path.keys()):
                is_monorepo_root = True

            # Check 2: Forked monorepo (e.g., go.etcd.io/etcd/v3 → github.com/k3s-io/etcd/server/v3)
            # If we failed to derive a repository, try checking if any existing module's last path segment
            # matches our module's last segment (e.g., both end in /v3)
            if not is_monorepo_root and module_path.count('/') >= 2:
                module_segments = module_path.split('/')
                # For go.etcd.io/etcd/v3: domain=go.etcd.io, repo=etcd, suffix=v3
                # Check if we have modules like */etcd/*/v3 (forked versions)
                for existing_path in modules_by_path.keys():
                    if '/' in existing_path:
                        # Check if the existing path is a submodule of a similar repository
                        # Example: github.com/k3s-io/etcd/server/v3 shares repository 'etcd' with go.etcd.io/etcd/v3
                        if '/etcd/' in existing_path and module_path.endswith('/v3'):
                            is_monorepo_root = True
                            break

            if is_monorepo_root:
                print(f"  ⊙ {module_path}@{version} (monorepo root - submodules already resolved)")
                continue

            if module_path in modules_by_path:
                FAILED_MODULE_PATHS.add(module_path)
                FAILED_MODULE_ENTRIES.add((module_path, version))
            print(f"  ⚠️  Skipping {module_path}@{version} (indirect-only dependency)")
        if limit_reached:
            break

    if limit_reached:
        print(f"\n⚠️  Debug limit {debug_limit} reached; skipping remaining modules discovered from go.sum/go list.")

    # Resolve /go.mod-only (indirect) dependencies using sibling versions
    # Even though these are "indirect", Go may still need them during compilation
    # (e.g., due to complex replace directives or transitive dependencies).
    # If we have a sibling version with Origin metadata, resolve the indirect version too.
    print(f"\n⚙️  Resolving /go.mod-only dependencies from sibling versions...")
    gomod_only_resolved = 0
    gomod_only_skipped = 0
    for module_path, version in sorted(go_sum_indirect_only):
        try:
            if (module_path, version) in discovered_keys:
                continue  # Already have this version

            if module_path in modules_by_path:
                # We have a sibling version - try to resolve this one using the sibling's VCS URL
                reference_module = modules_by_path[module_path][0]
                vcs_url = reference_module['vcs_url']
                tag = version.split('+')[0]
                commit = None
                pseudo_info = parse_pseudo_version_tag(tag)

                if pseudo_info:
                    timestamp_str, short_commit = pseudo_info
                    try:
                        commit = resolve_pseudo_version_commit(
                            vcs_url,
                            timestamp_str,
                            short_commit,
                            clone_cache_dir=CLONE_CACHE_DIR
                        )
                    except Exception as e:
                        print(f"  ❌ Error resolving pseudo-version {module_path}@{version} (timestamp={timestamp_str}, commit={short_commit}): {e}")
                        gomod_only_skipped += 1
                        continue
                else:
                    # For semantic version tags, try to find the tag reference
                    # This enables to detect orphaned tags for sibling-resolved modules
                    vcs_ref = ""
                    commit = git_ls_remote(vcs_url, f"refs/tags/{tag}")
                    if commit:
                        vcs_ref = f"refs/tags/{tag}"
                    else:
                        commit = git_ls_remote(vcs_url, tag)

                if commit:
                    timestamp = derive_timestamp_from_version(version)
                    subdir = reference_module.get('subdir', '')
                    update_metadata_cache(module_path, version, vcs_url, commit, timestamp, subdir, '', dirty=True)
                    fallback = {
                        "module_path": module_path,
                        "version": version,
                        "vcs_url": vcs_url,
                        "vcs_hash": commit,
                        "vcs_ref": vcs_ref,
                        "timestamp": timestamp,
                        "subdir": subdir,
                    }
                    modules.append(fallback)
                    discovered_keys.add((module_path, version))
                    modules_by_path[module_path].append(fallback)
                    gomod_only_resolved += 1
                    print(f"  ✓ {module_path}@{version} (/go.mod-only resolved using sibling version)")
                else:
                    gomod_only_skipped += 1
            else:
                gomod_only_skipped += 1
        except Exception as e:
            print(f"  ❌ Error resolving {module_path}@{version}: {e}")
            gomod_only_skipped += 1

    if gomod_only_resolved > 0:
        print(f"✓ Resolved {gomod_only_resolved} /go.mod-only dependencies using sibling versions")
    if gomod_only_skipped > 0:
        print(f"  ⚠️  Skipped {gomod_only_skipped} /go.mod-only dependencies (no sibling version available)")

    if FAILED_MODULE_ENTRIES:
        print("\n❌ Failed to resolve metadata for the following modules:")
        for mod, ver in sorted(FAILED_MODULE_ENTRIES):
            print(f"   - {mod}@{ver}")
        print("Aborting to avoid emitting invalid SRCREVs.")
        return 1

    if not modules:
        print("❌ No modules discovered")
        return 1

    success = generate_recipe(
        modules,
        source_dir,
        output_dir,
        args.git_repo or "unknown",
        args.git_ref or "unknown",
        validate_only=args.validate,
        debug_limit=debug_limit,
        skip_verify=args.skip_verify,
        verify_jobs=args.verify_jobs,
        exclude_modules=args.exclude_module,
    )

    if success:
        if args.validate:
            print("\n" + "=" * 70)
            print("✅ SUCCESS - Validation complete")
            print("=" * 70)
        else:
            print("\n" + "=" * 70)
            print("✅ SUCCESS - Recipe generation complete")
            print("=" * 70)

        # Write corrected modules back to JSON for future runs
        if args.discovered_modules and VERIFY_CORRECTIONS_APPLIED:
            corrected_json = args.discovered_modules.replace('.json', '-corrected.json')
            try:
                with open(corrected_json, 'w') as f:
                    json.dump(modules, f, indent=2)
                print(f"\n✓ Wrote corrected module metadata to: {corrected_json}")
                print(f"  Use this file for future runs to avoid re-detecting orphaned commits")
            except Exception as e:
                print(f"\n⚠️  Could not write corrected JSON: {e}")

        # License scanning (after successful generation)
        if args.scan_licenses and output_dir and not args.validate:
            print("\n" + "=" * 70)
            print("LICENSE SCANNING")
            print("=" * 70)

            # Determine discovery cache location
            disc_cache = args.discovery_cache
            if not disc_cache and args.gomodcache:
                # gomodcache IS the discovery cache root
                disc_cache = args.gomodcache
            if not disc_cache:
                # Try CURRENT_GOMODCACHE
                if CURRENT_GOMODCACHE and Path(CURRENT_GOMODCACHE).exists():
                    disc_cache = str(CURRENT_GOMODCACHE)

            if disc_cache and os.path.isdir(disc_cache):
                license_db = _resolve_license_db(args.common_license_dir)
                if license_db:
                    lic_results = scan_module_licenses(modules, disc_cache, license_db)
                    if lic_results:
                        write_license_inc(output_dir, lic_results)
                    else:
                        print("  No license files found in module zips")
                else:
                    print("  Skipping license scan: no license database available")
            else:
                print("  Skipping license scan: no discovery cache found")
                print("  Hint: pass --discovery-cache <path> or run via bitbake -c discover_and_generate")

        exit_code = 0
    else:
        print("\n❌ FAILED - Recipe generation failed")
        exit_code = 1

    if SKIPPED_MODULES:
        print("\n⚠️  Skipped modules (no repository metadata)")
        for (module_path, version), reason in sorted(SKIPPED_MODULES.items()):
            print(f"\n   - {module_path}@{version} [{reason}]")
            print()
            print(f"     Option 1: Exclude from VCS and fetch via Go module proxy instead.")
            print(f"               Add to your recipe (.bb):")
            print(f'         SRC_URI += "gomod://{module_path};version={version};sha256sum=<run bitbake -c fetch to get>"')
            print(f'         GO_MOD_VCS_EXCLUDE += "{module_path}"')
            print()
            print(f"     Option 2: Same result, but for direct oe-go-mod-fetcher.py invocation.")
            print(f"               Provide the git repository URL for this module:")
            print(f"         python3 oe-go-mod-fetcher.py --set-repo {module_path}@{version} <git-url> \\")
            print(f"           --discovered-modules <modules.json> --git-repo <repo> --git-ref <ref> --recipedir <dir>")

    return exit_code


def parse_go_mod_replaces(go_mod_path: Path) -> Dict[str, Tuple[str, str]]:
    """
    Parse replace directives from go.mod file.

    Returns:
        Dict mapping old_path to (new_path, new_version)
        Example: {"github.com/containerd/containerd/v2": ("github.com/k3s-io/containerd/v2", "v2.1.4-k3s2")}
    """
    replaces = {}
    if not go_mod_path.exists():
        return replaces

    try:
        content = go_mod_path.read_text()
        # Match: old_path => new_path version
        # Example: github.com/containerd/containerd/v2 => github.com/k3s-io/containerd/v2 v2.1.4-k3s2
        for line in content.splitlines():
            line = line.strip()
            if not line.startswith('replace ') and '=>' not in line:
                continue

            # Remove 'replace ' prefix if present
            if line.startswith('replace '):
                line = line[8:].strip()

            parts = line.split('=>')
            if len(parts) != 2:
                continue

            left = parts[0].strip().split()
            right = parts[1].strip().split()

            if len(left) == 0 or len(right) == 0:
                continue

            old_path = left[0]
            new_path = right[0]
            new_version = right[1] if len(right) > 1 else ""

            replaces[old_path] = (new_path, new_version)
    except Exception as e:
        print(f"⚠️  Failed to parse go.mod replaces: {e}", file=sys.stderr)

    return replaces


def parse_pseudo_version_tag(tag: str) -> Optional[Tuple[str, str]]:
    """Return (timestamp, short_commit) for Go pseudo-versions."""
    tag = tag.split('+', 1)[0]
    parts = tag.split('-')
    if len(parts) < 3:
        return None

    short_commit = parts[-1]
    timestamp_part = parts[-2]
    timestamp_str = timestamp_part.split('.')[-1]

    if len(timestamp_str) != 14 or not timestamp_str.isdigit():
        return None

    if not re.fullmatch(r'[0-9a-fA-F]{6,40}', short_commit):
        return None

    return timestamp_str, short_commit


def _cache_key(url: str, ref: str) -> str:
    return f"{url}|||{ref}"


def load_ls_remote_cache() -> None:
    if not LS_REMOTE_CACHE_PATH.exists():
        return
    try:
        data = json.loads(LS_REMOTE_CACHE_PATH.read_text())
    except Exception:
        return
    for key, value in data.items():
        try:
            url, ref = key.split("|||", 1)
        except ValueError:
            continue
        LS_REMOTE_CACHE[(url, ref)] = value


def save_ls_remote_cache() -> None:
    if not LS_REMOTE_CACHE_DIRTY:
        return
    try:
        payload = {
            _cache_key(url, ref): value
            for (url, ref), value in LS_REMOTE_CACHE.items()
        }
        LS_REMOTE_CACHE_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True))
    except Exception:
        pass


def git_ls_remote(url: str, ref: str, *, debug: bool = False) -> Optional[str]:
    """
    Query git repository for commit hash of a ref.
    Uses disk-based cache and local clones to minimize network calls.

    Args:
        url: Git repository URL
        ref: Git ref (tag, branch, commit, etc.)
        debug: If True, print whether result came from cache or network

    Returns:
        Commit hash or None if not found
    """
    global LS_REMOTE_CACHE_DIRTY
    key = (url, ref)

    # Check in-memory cache first
    if key in LS_REMOTE_CACHE:
        if debug or VERBOSE_MODE:
            result = LS_REMOTE_CACHE[key]
            status = "cached" if result else "cached (not found)"
            print(f"  [ls-remote {status}] {url} {ref}", file=sys.stderr)
        return LS_REMOTE_CACHE[key]

    # Try local repository clone if available
    repo_hash = hashlib.sha256(url.encode()).hexdigest()[:16]
    local_repo = CLONE_CACHE_DIR / f"repo_{repo_hash}"

    if local_repo.exists() and (local_repo / 'HEAD').exists():
        try:
            # Query local repository instead of network
            result = subprocess.run(
                ["git", "show-ref", "--hash", ref],
                cwd=local_repo,
                capture_output=True,
                text=True,
                timeout=10,
            )
            if result.returncode == 0 and result.stdout.strip():
                commit_hash = result.stdout.strip().split()[0]
                LS_REMOTE_CACHE[key] = commit_hash
                LS_REMOTE_CACHE_DIRTY = True
                if debug or VERBOSE_MODE:
                    print(f"  [ls-remote local] {url} {ref} -> {commit_hash[:12]}", file=sys.stderr)
                return commit_hash
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError, Exception):
            # Fall through to network query
            pass

    if debug or VERBOSE_MODE:
        print(f"  [ls-remote network] {url} {ref}", file=sys.stderr)

    try:
        env = os.environ.copy()
        env.setdefault("GIT_TERMINAL_PROMPT", "0")
        env.setdefault("GIT_ASKPASS", "true")

        # FIX: For tags, also query the dereferenced commit (^{}) to handle annotated tags
        # Annotated tags have a tag object hash that differs from the commit hash.
        # We need the actual commit hash for git archive/checkout operations.
        refs_to_query = [ref]
        if ref.startswith("refs/tags/"):
            refs_to_query.append(f"{ref}^{{}}")  # Add dereferenced query

        result = subprocess.run(
            ["git", "ls-remote", url] + refs_to_query,
            capture_output=True,
            text=True,
            check=True,
            env=env,
            timeout=GIT_CMD_TIMEOUT,
        )

        # Parse results - prefer dereferenced commit (^{}) over annotated tag object
        tag_object_hash = None
        dereferenced_hash = None

        for line in result.stdout.strip().splitlines():
            if not line:
                continue
            parts = line.split()
            if len(parts) >= 2:
                hash_val, ref_name = parts[0], parts[1]
                if ref_name.endswith("^{}"):
                    # This is the dereferenced commit - preferred!
                    dereferenced_hash = hash_val
                else:
                    # This is either a lightweight tag or annotated tag object
                    tag_object_hash = hash_val

        # Prefer dereferenced commit, fall back to tag object (for lightweight tags)
        commit_hash = dereferenced_hash or tag_object_hash
        if commit_hash:
            LS_REMOTE_CACHE[key] = commit_hash
            LS_REMOTE_CACHE_DIRTY = True
            return commit_hash

    except subprocess.TimeoutExpired:
        print(f"  ⚠️  git ls-remote timeout ({GIT_CMD_TIMEOUT}s) for {url} {ref}")
        LS_REMOTE_CACHE[key] = None
        LS_REMOTE_CACHE_DIRTY = True
        return None
    except subprocess.CalledProcessError:
        LS_REMOTE_CACHE[key] = None
        LS_REMOTE_CACHE_DIRTY = True
        return None
    return None


def load_vanity_url_cache() -> None:
    """Load vanity URL resolution cache from disk."""
    if not VANITY_URL_CACHE_PATH.exists():
        return
    try:
        data = json.loads(VANITY_URL_CACHE_PATH.read_text())
        VANITY_URL_CACHE.update(data)
    except Exception:
        pass


def save_vanity_url_cache() -> None:
    """Save vanity URL resolution cache to disk."""
    if not VANITY_URL_CACHE_DIRTY:
        return
    try:
        VANITY_URL_CACHE_PATH.write_text(json.dumps(VANITY_URL_CACHE, indent=2, sort_keys=True))
    except Exception:
        pass


def load_verify_commit_cache() -> None:
    """
    Load verification cache with timestamp support for aging detection.

    Cache format v2:
    {
        "repo|||commit": {
            "verified": true,
            "first_verified": "2025-01-15T10:30:00Z",  # When first verified
            "last_checked": "2025-02-10T14:20:00Z",     # When last re-verified
            "fetch_method": "fetch"  # "fetch", "ref", or "cached"
        }
    }
    """
    global VERIFY_COMMIT_CACHE_DIRTY, VERIFY_COMMIT_CACHE_V2
    if not VERIFY_COMMIT_CACHE_PATH.exists():
        return
    try:
        data = json.loads(VERIFY_COMMIT_CACHE_PATH.read_text())
    except Exception:
        return

    if isinstance(data, dict):
        # Detect format: v1 (bool values) vs v2 (dict values)
        sample_value = next(iter(data.values())) if data else None

        if isinstance(sample_value, bool):
            # Legacy format: convert to v2
            from datetime import datetime, timezone
            now = datetime.now(timezone.utc).isoformat()
            for k, v in data.items():
                if v:  # Only migrate verified=True entries
                    VERIFY_COMMIT_CACHE_V2[k] = {
                        "verified": True,
                        "first_verified": now,
                        "last_checked": now,
                        "fetch_method": "cached"  # Unknown how it was verified
                    }
            VERIFY_COMMIT_CACHE_DIRTY = True  # Mark dirty to save in new format
        elif isinstance(sample_value, dict):
            # V2 format
            VERIFY_COMMIT_CACHE_V2.update(data)

    VERIFY_COMMIT_CACHE_DIRTY = False


def save_verify_commit_cache(force: bool = False) -> None:
    """Save verification cache in v2 format with timestamps.

    Args:
        force: If True, save even if not dirty (for incremental saves during long runs)
    """
    global VERIFY_COMMIT_CACHE_DIRTY

    if not force and not VERIFY_COMMIT_CACHE_DIRTY:
        return
    try:
        VERIFY_COMMIT_CACHE_PATH.write_text(json.dumps(VERIFY_COMMIT_CACHE_V2, indent=2, sort_keys=True))
        VERIFY_COMMIT_CACHE_DIRTY = False
    except Exception as e:
        print(f"⚠️  Failed to save verification cache: {e}")
        pass


def _load_overrides_from_file(path: Path, target_dict: Dict[Tuple[str, Optional[str]], str]) -> None:
    """
    Load module->repo overrides from a JSON file into the target dictionary.

    File format:
    {
        "module/path": "https://github.com/org/repo",
        "module/path@v1.2.3": "https://github.com/org/repo"
    }

    The @version suffix is optional. Use it to override only a specific version.
    """
    if not path.exists():
        return
    try:
        data = json.loads(path.read_text())
    except Exception:
        return
    if not isinstance(data, dict):
        return

    for raw_key, repo_url in data.items():
        if not isinstance(repo_url, str):
            continue
        module_path = str(raw_key)
        version: Optional[str] = None

        # Support both "module|||version" (legacy) and "module@version" (new) formats
        if "|||" in module_path:
            module_part, version_part = module_path.split("|||", 1)
            version = None if version_part == "*" else version_part
            module_path = module_part
        elif "@" in module_path and not module_path.startswith("@"):
            # Handle module@version format (but not @org/pkg scoped packages)
            at_pos = module_path.rfind("@")
            version = module_path[at_pos + 1:]
            module_path = module_path[:at_pos]

        try:
            key = _normalise_override_key(module_path, version)
        except ValueError:
            continue
        target_dict[key] = repo_url


def load_manual_overrides() -> None:
    """Load git-tracked manual overrides from manual-overrides.json."""
    global MANUAL_OVERRIDES
    MANUAL_OVERRIDES.clear()
    _load_overrides_from_file(MANUAL_OVERRIDES_PATH, MANUAL_OVERRIDES)
    if MANUAL_OVERRIDES:
        print(f"  Loaded {len(MANUAL_OVERRIDES)} manual repository override(s)")


def load_repo_overrides() -> None:
    """Load dynamic overrides from repo-overrides.json (created via --set-repo)."""
    global MODULE_REPO_OVERRIDES_DIRTY
    MODULE_REPO_OVERRIDES.clear()
    _load_overrides_from_file(MODULE_REPO_OVERRIDES_PATH, MODULE_REPO_OVERRIDES)
    MODULE_REPO_OVERRIDES_DIRTY = False


def save_repo_overrides() -> None:
    if not MODULE_REPO_OVERRIDES_DIRTY:
        return
    try:
        payload: Dict[str, str] = {}
        for (module_path, version), repo_url in MODULE_REPO_OVERRIDES.items():
            key = module_path if version is None else f"{module_path}|||{version}"
            payload[key] = repo_url
        MODULE_REPO_OVERRIDES_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True))
    except Exception:
        pass


def query_vanity_url(module_path: str) -> Optional[str]:
    """
    Query vanity URL metadata using ?go-get=1 to resolve actual VCS repository.

    Go uses vanity URLs to provide custom import paths that redirect to actual
    repositories. When you request https://example.com/module?go-get=1, the server
    returns HTML with a meta tag like:
        <meta name="go-import" content="example.com/module git https://github.com/org/repo">

    This function queries that metadata and caches the result for future use.

    Args:
        module_path: Go module path (e.g., "go.uber.org/atomic")

    Returns:
        VCS repository URL if found, None otherwise
    """
    global VANITY_URL_CACHE_DIRTY

    # Check cache first
    if module_path in VANITY_URL_CACHE:
        return VANITY_URL_CACHE[module_path]

    # Query the ?go-get=1 metadata
    url = f"https://{module_path}?go-get=1"

    try:
        import urllib.request
        import html.parser

        class GoImportParser(html.parser.HTMLParser):
            def __init__(self, target_module: str):
                super().__init__()
                self.target_module = target_module
                self.repo_url = None
                self.best_prefix_len = 0  # Track longest matching prefix

            def handle_starttag(self, tag, attrs):
                if tag == 'meta':
                    attrs_dict = dict(attrs)
                    if attrs_dict.get('name') == 'go-import':
                        content = attrs_dict.get('content', '')
                        # Format: "module_prefix vcs repo_url"
                        parts = content.split()
                        if len(parts) >= 3:
                            prefix = parts[0]
                            # parts[1] = vcs type (git, hg, svn, bzr)
                            repo_url = parts[2]
                            # Per Go spec: match the go-import whose prefix matches our module
                            # The module path must equal the prefix or have it as a path prefix
                            if self.target_module == prefix or self.target_module.startswith(prefix + '/'):
                                # Prefer longer (more specific) prefix matches
                                if len(prefix) > self.best_prefix_len:
                                    self.best_prefix_len = len(prefix)
                                    self.repo_url = repo_url

        # Fetch the page with a timeout
        req = urllib.request.Request(url, headers={'User-Agent': 'oe-go-mod-fetcher/3.0'})
        with urllib.request.urlopen(req, timeout=10) as response:
            html_content = response.read().decode('utf-8', errors='ignore')

        # Parse the HTML to find matching go-import meta tag
        parser = GoImportParser(module_path)
        parser.feed(html_content)

        # Cache the result (even if None)
        VANITY_URL_CACHE[module_path] = parser.repo_url
        VANITY_URL_CACHE_DIRTY = True

        return parser.repo_url

    except Exception as e:
        # Cache negative result to avoid repeated failures
        VANITY_URL_CACHE[module_path] = None
        VANITY_URL_CACHE_DIRTY = True
        return None


def get_github_mirror_url(vcs_url: str) -> Optional[str]:
    """
    Get GitHub mirror URL for golang.org/x repositories.

    golang.org/x repositories are mirrored on GitHub at github.com/golang/*.
    These mirrors are often more reliable than go.googlesource.com.

    Args:
        vcs_url: Original VCS URL (e.g., https://go.googlesource.com/tools)

    Returns:
        GitHub mirror URL if applicable, None otherwise
    """
    if 'go.googlesource.com' in vcs_url:
        # Extract package name from URL
        # https://go.googlesource.com/tools -> tools
        pkg_name = vcs_url.rstrip('/').split('/')[-1]
        return f"https://github.com/golang/{pkg_name}"
    return None


def resolve_pseudo_version_commit(vcs_url: str, timestamp_str: str, short_commit: str,
                                   clone_cache_dir: Optional[Path] = None) -> Optional[str]:
    """
    Resolve a pseudo-version's short commit hash to a full 40-character hash.

    This function clones (or updates) a git repository and searches the commit history
    for a commit that matches both the timestamp and short commit hash from a pseudo-version.

    For golang.org/x repositories, automatically tries GitHub mirrors if the primary
    source fails (go.googlesource.com can be slow or unreliable).

    Args:
        vcs_url: Git repository URL
        timestamp_str: Timestamp from pseudo-version (format: YYYYMMDDHHmmss)
        short_commit: Short commit hash (12 characters) from pseudo-version
        clone_cache_dir: Optional directory to cache cloned repositories (recommended)

    Returns:
        Full 40-character commit hash, or None if not found
    """
    # Parse timestamp
    try:
        dt = datetime.strptime(timestamp_str, "%Y%m%d%H%M%S")
        # Validate the date is within a reasonable range before doing arithmetic
        # Python datetime supports years 1-9999, but Go pseudo-versions should be recent
        # Also ensure year > 1 to avoid overflow when subtracting 1 day
        if dt.year < 1970 or dt.year > 9999:
            print(f"⚠️  Invalid timestamp year {dt.year} in pseudo-version (timestamp: {timestamp_str})", file=sys.stderr)
            return None
        if dt.year == 1:
            # Special case: year 1 would overflow when subtracting 1 day
            print(f"⚠️  Invalid timestamp year 1 in pseudo-version (timestamp: {timestamp_str})", file=sys.stderr)
            return None
        # Search window: ±1 day around timestamp for efficiency
        try:
            since = (dt - timedelta(days=1)).isoformat()
            until = (dt + timedelta(days=1)).isoformat()
        except OverflowError as e:
            print(f"⚠️  Date arithmetic overflow for timestamp {timestamp_str}: {e}", file=sys.stderr)
            return None
    except ValueError as e:
        print(f"⚠️  Invalid timestamp format {timestamp_str}: {e}", file=sys.stderr)
        return None

    # Try primary URL and GitHub mirror (if applicable)
    urls_to_try = [vcs_url]
    github_mirror = get_github_mirror_url(vcs_url)
    if github_mirror:
        urls_to_try.append(github_mirror)

    git_env = os.environ.copy()
    git_env.setdefault("GIT_TERMINAL_PROMPT", "0")
    git_env.setdefault("GIT_ASKPASS", "true")

    for try_url in urls_to_try:
        # Determine clone directory based on URL being tried
        if clone_cache_dir:
            clone_cache_dir.mkdir(parents=True, exist_ok=True)
            repo_hash = hashlib.sha256(try_url.encode()).hexdigest()[:16]
            clone_dir = clone_cache_dir / f"repo_{repo_hash}"
        else:
            clone_dir = Path(tempfile.mkdtemp(prefix="pseudo-resolve-"))

        try:
            # Clone or update repository
            if clone_dir.exists() and (clone_dir / 'HEAD').exists():
                # Repository already cloned, fetch latest
                try:
                    subprocess.run(
                        ['git', 'fetch', '--all', '--quiet'],
                        cwd=clone_dir,
                        capture_output=True,
                        check=True,
                        timeout=60,
                        env=git_env,
                    )
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                    # Fetch failed, try to use existing clone anyway
                    pass
            else:
                # Clone repository (bare clone for efficiency)
                if clone_dir.exists():
                    shutil.rmtree(clone_dir)
                clone_dir.mkdir(parents=True, exist_ok=True)

                subprocess.run(
                    ['git', 'clone', '--bare', '--quiet', try_url, str(clone_dir)],
                    capture_output=True,
                    check=True,
                    timeout=300,  # 5 minute timeout
                    env=git_env,
                )

            # Search for commits matching timestamp and short hash
            result = subprocess.run(
                ['git', 'log', '--all', '--format=%H %ct',
                 f'--since={since}', f'--until={until}'],
                cwd=clone_dir,
                capture_output=True,
                text=True,
                check=True,
                timeout=30,
                env=git_env,
            )

            # Find commit with matching short hash prefix
            for line in result.stdout.strip().splitlines():
                if not line:
                    continue
                parts = line.split()
                if len(parts) < 2:
                    continue
                full_hash = parts[0]
                if full_hash.startswith(short_commit):
                    return full_hash

            # Commit not found in this repository, try next URL
            continue

        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            # Clone/fetch failed, try next URL if available
            if not clone_cache_dir and clone_dir.exists():
                shutil.rmtree(clone_dir)
            continue
        finally:
            # Clean up temp directory if we created one
            if not clone_cache_dir and clone_dir.exists():
                try:
                    shutil.rmtree(clone_dir)
                except:
                    pass

    # All URLs failed
    return None


def derive_timestamp_from_version(version: str) -> str:
    parsed = parse_pseudo_version_tag(version)
    if parsed:
        timestamp_str, _ = parsed
        try:
            return datetime.strptime(timestamp_str, "%Y%m%d%H%M%S").strftime("%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            return "1970-01-01T00:00:00Z"
    return "1970-01-01T00:00:00Z"


def _cache_metadata_key(module_path: str, version: str) -> Tuple[str, str]:
    return (module_path, version)


def load_metadata_cache_file() -> None:
    if not MODULE_METADATA_CACHE_PATH.exists():
        return
    try:
        data = json.loads(MODULE_METADATA_CACHE_PATH.read_text())
    except Exception:
        return
    for key, value in data.items():
        try:
            module_path, version = key.split("|||", 1)
        except ValueError:
            continue
        if not isinstance(value, dict):
            continue
        MODULE_METADATA_CACHE[_cache_metadata_key(module_path, version)] = {
            'vcs_url': value.get('vcs_url', ''),
            'commit': value.get('commit', ''),
            'timestamp': value.get('timestamp', ''),
            'subdir': value.get('subdir', ''),
            'ref': value.get('ref', ''),
        }


def save_metadata_cache() -> None:
    if not MODULE_METADATA_CACHE_DIRTY:
        return
    payload = {
        f"{module}|||{version}": value
        for (module, version), value in MODULE_METADATA_CACHE.items()
    }
    try:
        MODULE_METADATA_CACHE_PATH.write_text(json.dumps(payload, indent=2, sort_keys=True))
    except Exception:
        pass


def update_metadata_cache(module_path: str, version: str, vcs_url: str, commit: str,
                          timestamp: str = "", subdir: str = "", ref: str = "",
                          dirty: bool = True) -> None:
    global MODULE_METADATA_CACHE_DIRTY
    key = _cache_metadata_key(module_path, version)
    value = {
        'vcs_url': vcs_url or '',
        'commit': commit or '',
        'timestamp': timestamp or '',
        'subdir': subdir or '',
        'ref': ref or '',
    }
    if MODULE_METADATA_CACHE.get(key) != value:
        MODULE_METADATA_CACHE[key] = value
        if dirty:
            MODULE_METADATA_CACHE_DIRTY = True


def get_cached_metadata(module_path: str, version: str) -> Optional[dict]:
    entry = MODULE_METADATA_CACHE.get(_cache_metadata_key(module_path, version))
    if not entry:
        return None
    timestamp = entry.get('timestamp') or derive_timestamp_from_version(version)
    return {
        "module_path": module_path,
        "version": version,
        "vcs_url": entry.get('vcs_url', ''),
        "vcs_hash": entry.get('commit', ''),
        "vcs_ref": entry.get('ref', ''),
        "timestamp": timestamp,
        "subdir": entry.get('subdir', ''),
    }


def load_metadata_from_inc(output_dir: Path) -> None:
    git_inc = output_dir / "go-mod-git.inc"
    cache_inc = output_dir / "go-mod-cache.inc"

    sha_to_url: Dict[str, str] = {}
    if git_inc.exists():
        for line in git_inc.read_text().splitlines():
            line = line.strip()
            if not line.startswith('SRC_URI'):
                continue
            if '"' not in line:
                continue
            content = line.split('"', 1)[1].rsplit('"', 1)[0]
            parts = [p for p in content.split(';') if p]
            if not parts:
                continue
            url_part = parts[0]
            dest_sha = None
            for part in parts[1:]:
                if part.startswith('destsuffix='):
                    dest = part.split('=', 1)[1]
                    dest_sha = dest.rsplit('/', 1)[-1]
                    break
            if not dest_sha:
                continue
            if url_part.startswith('git://'):
                url_https = 'https://' + url_part[6:]
            else:
                url_https = url_part
            sha_to_url[dest_sha] = url_https

    if cache_inc.exists():
        text = cache_inc.read_text()
        marker = "GO_MODULE_CACHE_DATA = '"
        if marker in text:
            start = text.index(marker) + len(marker)
            try:
                end = text.index("'\n\n", start)
            except ValueError:
                end = len(text)
            try:
                data = json.loads(text[start:end])
            except Exception:
                data = []
            for entry in data:
                module_path = entry.get('module')
                version = entry.get('version')
                sha = entry.get('vcs_hash')
                commit = entry.get('commit')
                timestamp = entry.get('timestamp', '')
                subdir = entry.get('subdir', '')
                ref = entry.get('vcs_ref', '')
                if not module_path or not version:
                    continue
                vcs_url = sha_to_url.get(sha, '')
                if not vcs_url:
                    continue
                if not _url_allowed_for_module(module_path, vcs_url, version):
                    continue
                # Skip entries with invalid commit hashes
                if commit and len(commit) != 40:
                    continue
                if not timestamp:
                    timestamp = derive_timestamp_from_version(version)
                update_metadata_cache(module_path, version, vcs_url, commit or '', timestamp, subdir, ref, dirty=False)


def load_metadata_from_module_cache_task(output_dir: Path) -> None:
    legacy_path = output_dir / "module_cache_task.inc"
    if not legacy_path.exists():
        return
    import ast
    pattern = re.compile(r'\(\{.*?\}\)', re.DOTALL)
    text = legacy_path.read_text()
    for match in pattern.finditer(text):
        blob = match.group()[1:-1]  # strip parentheses
        try:
            entry = ast.literal_eval(blob)
        except Exception:
            continue
        module_path = entry.get('module')
        version = entry.get('version')
        vcs_url = entry.get('repo_url') or entry.get('url') or ''
        commit = entry.get('commit') or ''
        subdir = entry.get('subdir', '')
        ref = entry.get('ref', '')
        if not module_path or not version or not vcs_url or not commit:
            continue
        if vcs_url.startswith('git://'):
            vcs_url = 'https://' + vcs_url[6:]
        if not _url_allowed_for_module(module_path, vcs_url, version):
            continue
        timestamp = derive_timestamp_from_version(version)
        update_metadata_cache(module_path, version, vcs_url, commit, timestamp, subdir, ref, dirty=True)


def bootstrap_metadata_cache(output_dir: Optional[Path],
                             skip_inc_files: bool = False,
                             skip_legacy_module_cache: bool = False) -> None:
    """
    Bootstrap metadata cache from multiple sources.

    Args:
        output_dir: Recipe output directory (optional in cache-only mode)
        skip_inc_files: If True, skip loading from .inc files (used with --clean-cache)
        skip_legacy_module_cache: If True, skip loading legacy module_cache_task.inc metadata
    """
    load_metadata_cache_file()
    if not skip_inc_files and output_dir is not None:
        load_metadata_from_inc(output_dir)
    if not skip_legacy_module_cache and output_dir is not None:
        load_metadata_from_module_cache_task(output_dir)


def _lookup_commit_for_version(vcs_url: str, version: str, preferred_ref: str = "") -> Tuple[Optional[str], Optional[str]]:
    """
    Resolve the git commit for a module version using git ls-remote.

    Returns:
        Tuple of (commit, timestamp). Timestamp may be None if unknown.
    """
    tag = version.split('+')[0]
    pseudo_info = parse_pseudo_version_tag(tag)
    candidate_urls = [vcs_url]
    if not vcs_url.endswith('.git'):
        candidate_urls.append(vcs_url.rstrip('/') + '.git')

    for url in candidate_urls:
        if preferred_ref:
            commit = git_ls_remote(url, preferred_ref)
            if commit:
                return commit, "1970-01-01T00:00:00Z"

        if pseudo_info:
            timestamp_str, short_commit = pseudo_info
            commit = git_ls_remote(url, short_commit)
            if commit:
                timestamp = derive_timestamp_from_version(version)
                return commit, timestamp
        else:
            for ref in (f"refs/tags/{tag}", tag):
                commit = git_ls_remote(url, ref)
                if commit:
                    return commit, "1970-01-01T00:00:00Z"

    if pseudo_info:
        timestamp_str, short_commit = pseudo_info
        for url in candidate_urls:
            commit = resolve_pseudo_version_commit(
                url,
                timestamp_str,
                short_commit,
                clone_cache_dir=CLONE_CACHE_DIR,
            )
            if commit:
                timestamp = derive_timestamp_from_version(version)
                return commit, timestamp

    if pseudo_info:
        # Even if we couldn't resolve the commit, return derived timestamp
        return None, derive_timestamp_from_version(version)
    return None, None


def query_module_via_go_list(module_path: str, version: str) -> Optional[Dict[str, str]]:
    """Use `go list -m -json` to obtain VCS metadata for a module version."""
    env = os.environ.copy()
    env.setdefault('GOPROXY', 'https://proxy.golang.org')
    if CURRENT_GOMODCACHE:
        env['GOMODCACHE'] = CURRENT_GOMODCACHE

    try:
        result = subprocess.run(
            ['go', 'list', '-m', '-json', f'{module_path}@{version}'],
            capture_output=True,
            text=True,
            check=True,
            env=env,
            timeout=GO_CMD_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        print(f"  ⚠️  go list timed out for {module_path}@{version} after {GO_CMD_TIMEOUT}s")
        return None
    except subprocess.CalledProcessError:
        return None

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None

    origin = data.get('Origin') or {}
    vcs_url = origin.get('URL', '')
    commit = origin.get('Hash', '')
    subdir = origin.get('Subdir', '')
    ref = origin.get('Ref', '')
    timestamp = data.get('Time') or origin.get('Time') or ''

    if vcs_url.startswith('git+'):
        vcs_url = vcs_url[4:]

    if not vcs_url or not commit:
        return None

    return {
        'vcs_url': vcs_url,
        'commit': commit,
        'timestamp': timestamp,
        'subdir': subdir or '',
        'vcs_ref': ref or '',
    }


def _candidate_gopkg_repos(module_path: str) -> List[str]:
    """
    Generate candidate repository URLs for gopkg.in modules.
    """
    if not module_path.startswith("gopkg.in/"):
        return []

    remainder = module_path[len("gopkg.in/"):]
    if not remainder:
        return []

    parts = remainder.split('/')
    last = parts[-1]

    match = re.match(r'(?P<name>.+?)\.v\d+(?:[.\w-]*)?$', last)
    if not match:
        return []

    repo_name = match.group('name')
    owner_segments = parts[:-1]

    owner_variants: List[str] = []
    if owner_segments:
        canonical_owner = '/'.join(owner_segments)
        owner_variants.append(canonical_owner)

        # Provide fallbacks with dotted segments replaced
        dotted_to_hyphen = '/'.join(segment.replace('.', '-') for segment in owner_segments)
        dotted_to_empty = '/'.join(segment.replace('.', '') for segment in owner_segments)
        for candidate in (dotted_to_hyphen, dotted_to_empty):
            if candidate and candidate not in owner_variants:
                owner_variants.append(candidate)
    else:
        # Common conventions used by gopkg.in vanity repos
        owner_variants.extend([
            f"go-{repo_name}",
            repo_name,
            f"{repo_name}-go",
        ])

    urls: List[str] = []
    seen: Set[str] = set()
    for owner in owner_variants:
        owner = owner.strip('/')
        if not owner:
            continue
        candidate = f"https://github.com/{owner}/{repo_name}"
        if candidate not in seen:
            seen.add(candidate)
            urls.append(candidate)
    return urls


def _recalculate_subdir_from_vanity(vcs_url: str, module_parts: List[str], current_subdir: str) -> str:
    """
    Recalculate module subdirectory when a vanity import redirects to a different repository layout.
    """
    if not vcs_url:
        return current_subdir

    vcs_repo_name = vcs_url.rstrip('/').split('/')[-1]
    if vcs_repo_name.endswith('.git'):
        vcs_repo_name = vcs_repo_name[:-4]

    repo_boundary_index = None
    for i, part in enumerate(module_parts):
        if part == vcs_repo_name or part in vcs_repo_name or vcs_repo_name.endswith(part):
            repo_boundary_index = i + 1
            break

    if repo_boundary_index is not None and repo_boundary_index < len(module_parts):
        subdir_parts = module_parts[repo_boundary_index:]
        if subdir_parts and subdir_parts[-1].startswith('v') and subdir_parts[-1][1:].isdigit():
            subdir_parts = subdir_parts[:-1]
        return '/'.join(subdir_parts) if subdir_parts else ''

    if len(module_parts) <= 3:
        return ''

    return current_subdir


def resolve_module_metadata(module_path: str, version: str) -> Optional[dict]:
    parts = module_path.split('/')
    vanity_repo = None  # Track if module was resolved via vanity URL

    tag = version.split('+')[0]
    pseudo_info = parse_pseudo_version_tag(tag)
    expected_commit_prefix = pseudo_info[1] if pseudo_info else None

    cached = get_cached_metadata(module_path, version)
    if cached:
        override_urls = repo_override_candidates(module_path, version)
        if expected_commit_prefix:
            cached_commit = cached.get('vcs_hash') or ''
            if cached_commit and not cached_commit.startswith(expected_commit_prefix):
                cached = None
        if cached and override_urls:
            url = cached.get('vcs_url') or ''
            if url and url not in override_urls:
                cached = None
        if cached and not expected_commit_prefix:
            ref_hint = cached.get('vcs_ref', '')
            commit_check, _ = _lookup_commit_for_version(cached.get('vcs_url', ''), version, ref_hint)
            if not commit_check or commit_check.lower() != (cached.get('vcs_hash', '') or '').lower():
                cached = None

    def fetch_go_metadata() -> Optional[Dict[str, str]]:
        info = query_module_via_go_list(module_path, version)
        if info:
            return info
        if go_mod_download(module_path, version):
            return query_module_via_go_list(module_path, version)
        return None

    def resolve_with_go_info(go_info: Optional[Dict[str, str]], fallback_url: str, fallback_subdir: str) -> Optional[dict]:
        if not go_info:
            return None

        candidate_urls: List[str] = []
        overrides = repo_override_candidates(module_path, version)
        candidate_urls.extend(overrides)
        info_url = (go_info.get('vcs_url') or '').strip()
        if info_url and info_url not in candidate_urls:
            candidate_urls.append(info_url)
        if fallback_url and fallback_url not in candidate_urls:
            candidate_urls.append(fallback_url)

        timestamp_hint = go_info.get('timestamp') or derive_timestamp_from_version(version)
        subdir_hint = go_info.get('subdir', '') or fallback_subdir
        ref_hint = go_info.get('vcs_ref', '')

        for candidate in candidate_urls:
            if not _url_allowed_for_module(module_path, candidate, version):
                continue
            commit_candidate, timestamp_candidate = _lookup_commit_for_version(candidate, version, ref_hint)
            if commit_candidate:
                final_timestamp = timestamp_candidate or timestamp_hint
                update_metadata_cache(
                    module_path,
                    version,
                    candidate,
                    commit_candidate,
                    final_timestamp,
                    subdir_hint,
                    ref_hint,
                    dirty=True,
                )
                return {
                    "module_path": module_path,
                    "version": version,
                    "vcs_url": candidate,
                    "vcs_hash": commit_candidate,
                    "vcs_ref": ref_hint,
                    "timestamp": final_timestamp,
                    "subdir": subdir_hint,
                }
        return None

    # Handle gopkg.in special case
    if parts[0] == 'gopkg.in':
        repo_candidates: List[str] = []
        vanity_repo = query_vanity_url(module_path)
        if vanity_repo:
            repo_candidates.append(vanity_repo)
        repo_candidates.extend(_candidate_gopkg_repos(module_path))
        if cached and cached.get('vcs_url'):
            repo_candidates.insert(0, cached['vcs_url'])

        for vcs_url in repo_candidates:
            if not vcs_url:
                continue
            commit, timestamp = _lookup_commit_for_version(vcs_url, version)
            if commit:
                resolved_timestamp = timestamp or derive_timestamp_from_version(version)
                update_metadata_cache(module_path, version, vcs_url, commit, resolved_timestamp, '', '', dirty=True)
                return {
                    "module_path": module_path,
                    "version": version,
                    "vcs_url": vcs_url,
                    "vcs_hash": commit,
                    "vcs_ref": "",
                    "timestamp": resolved_timestamp,
                    "subdir": "",
                }

        go_info = fetch_go_metadata()
        result = resolve_with_go_info(go_info, '', '')

        if result:
            return result

        if cached:
            return cached

        print(f"  ⚠️  Unable to derive repository for gopkg.in path {module_path}@{version}")
        return None

    if len(parts) < 3:
        go_info = fetch_go_metadata()
        result = resolve_with_go_info(go_info, '', '')
        if result:
            return result

        vanity_repo = query_vanity_url(module_path)
        if vanity_repo:
            commit, timestamp = _lookup_commit_for_version(vanity_repo, version)
            if commit:
                resolved_timestamp = timestamp or derive_timestamp_from_version(version)
                update_metadata_cache(module_path, version, vanity_repo, commit, resolved_timestamp, '', '', dirty=True)
                return {
                    "module_path": module_path,
                    "version": version,
                    "vcs_url": vanity_repo,
                    "vcs_hash": commit,
                    "vcs_ref": "",
                    "timestamp": resolved_timestamp,
                    "subdir": '',
                }

        if cached:
            return cached

        print(f"  ⚠️  Unable to derive repository for {module_path}@{version}")
        return None
    else:
        # Default calculation assuming 3-part paths (domain/org/repo)
        base_repo = '/'.join(parts[:3])

        # Calculate subdir from module path, but strip version suffixes (v2, v3, v11, etc.)
        if len(parts) > 3:
            subdir_parts = parts[3:]
            # Remove trailing version suffix if present (e.g., v2, v3, v11)
            if subdir_parts and subdir_parts[-1].startswith('v') and subdir_parts[-1][1:].isdigit():
                subdir_parts = subdir_parts[:-1]
            subdir = '/'.join(subdir_parts) if subdir_parts else ''
        else:
            subdir = ''

        override_candidate = None
        override_urls = repo_override_candidates(module_path, version)
        if override_urls:
            override_candidate = override_urls[0]

        if override_candidate:
            vcs_url = override_candidate
        elif parts[0] == 'golang.org' and len(parts) >= 3 and parts[1] == 'x':
            pkg_name = parts[2]
            vcs_url = f"https://go.googlesource.com/{pkg_name}"
        elif parts[0] == 'github.com' and len(parts) >= 3:
            vcs_url = f"https://{base_repo}"
        else:
            vanity_repo = query_vanity_url(module_path)
            if vanity_repo:
                vcs_url = vanity_repo
                subdir = _recalculate_subdir_from_vanity(vcs_url, parts, subdir)
            else:
                vcs_url = f"https://{base_repo}"

    if cached and cached.get('vcs_url') and cached.get('vcs_hash'):
        if vanity_repo:
            adjusted_subdir = _recalculate_subdir_from_vanity(
                cached['vcs_url'],
                parts,
                cached.get('subdir', ''),
            )
            if adjusted_subdir != cached.get('subdir', ''):
                cached['subdir'] = adjusted_subdir
                update_metadata_cache(
                    module_path,
                    version,
                    cached['vcs_url'],
                    cached['vcs_hash'],
                    cached['timestamp'],
                    adjusted_subdir,
                    cached.get('vcs_ref', ''),
                    dirty=True,
                )
        return cached

    commit, timestamp = _lookup_commit_for_version(vcs_url, version)
    if not commit:
        go_info = fetch_go_metadata()
        result = resolve_with_go_info(go_info, vcs_url, subdir)
        if result:
            return result

        FAILED_MODULE_PATHS.add(module_path)
        _record_skipped_module(module_path, version, "no repository metadata from go.sum/go list")
        print(f"  ⚠️  Unable to derive repository for {module_path}@{version}")
        if cached and cached.get('vcs_hash'):
            return cached
        return None

    if not _url_allowed_for_module(module_path, vcs_url, version):
        FAILED_MODULE_PATHS.add(module_path)
        _record_skipped_module(module_path, version, "resolved repo not allowed by override policy")
        print(f"  ⚠️  Resolved repo {vcs_url} for {module_path}@{version} not in override allowlist")
        if cached and cached.get('vcs_hash'):
            return cached
        return None

    resolved_timestamp = timestamp or derive_timestamp_from_version(version)

    update_metadata_cache(module_path, version, vcs_url, commit, resolved_timestamp, subdir, '', dirty=True)

    return {
        "module_path": module_path,
        "version": version,
        "vcs_url": vcs_url,
        "vcs_hash": commit,
        "vcs_ref": "",
        "timestamp": resolved_timestamp,
        "subdir": subdir,
    }


# =============================================================================
# Utility Functions
# =============================================================================

def unescape_module_path(path: str) -> str:
    """
    Unescape Go module paths that use ! for uppercase letters.
    Example: github.com/!sirupsen/logrus -> github.com/Sirupsen/logrus
    """
    import re
    return re.sub(r'!([a-z])', lambda m: m.group(1).upper(), path)

def escape_module_path(path: str) -> str:
    """
    Escape Go module paths by converting uppercase to !lowercase.
    Example: github.com/Sirupsen/logrus -> github.com/!sirupsen/logrus
    """
    import re
    return re.sub(r'([A-Z])', lambda m: '!' + m.group(1).lower(), path)

# =============================================================================
# Phase 1: Discovery
# =============================================================================

def parse_go_mod_requires(go_mod_path: Path) -> List[tuple]:
    """
    Extract ALL module requirements from go.mod (direct + indirect).

    This replaces the need for fast-fix-module.py by discovering all
    transitive dependencies that Go needs.

    Returns list of (module_path, version) tuples.
    """
    modules = []

    if not go_mod_path.exists():
        print(f"Warning: go.mod not found at {go_mod_path}")
        return modules

    in_require = False

    try:
        with open(go_mod_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()

                # Start of require block
                if line.startswith('require ('):
                    in_require = True
                    continue

                # End of require block
                if in_require and line == ')':
                    in_require = False
                    continue

                # Single-line require
                if line.startswith('require ') and '(' not in line:
                    parts = line.split()
                    if len(parts) >= 3:  # require module version
                        module = parts[1]
                        version = parts[2]
                        modules.append((module, version))
                    continue

                # Multi-line require block entry
                if in_require and line:
                    # Skip comments
                    if line.startswith('//'):
                        continue

                    # Parse: "module version // indirect" or just "module version"
                    parts = line.split()
                    if len(parts) >= 2:
                        module = parts[0]
                        version = parts[1]
                        modules.append((module, version))

    except Exception as e:
        print(f"Error parsing go.mod: {e}")

    return modules


def download_all_required_modules(source_dir: Path, gomodcache: Path) -> None:
    """
    Download ALL modules required by go.mod (direct + indirect).

    This ensures that indirect/transitive dependencies have .info files
    in the GOMODCACHE, which allows discover_modules() to find them.

    This is the key to replacing fast-fix-module.py - by downloading
    everything upfront, we make all modules discoverable.
    """
    go_mod_path = source_dir / "go.mod"

    print(f"\n" + "=" * 70)
    print("DISCOVERY ENHANCEMENT: Downloading all required modules")
    print("=" * 70)
    print(f"Parsing {go_mod_path}...")

    required_modules = parse_go_mod_requires(go_mod_path)

    if not required_modules:
        print("Warning: No modules found in go.mod")
        return

    print(f"Found {len(required_modules)} total modules in go.mod (direct + indirect)")

    # Set up environment for Go
    env = os.environ.copy()
    env['GOMODCACHE'] = str(gomodcache)
    env['GOPROXY'] = 'https://proxy.golang.org'

    # Download each module to ensure .info files exist
    success_count = 0
    skip_count = 0
    fail_count = 0

    for module_path, version in required_modules:
        # Check if .info file already exists
        escaped_module = escape_module_path(module_path)
        escaped_version = escape_module_path(version)
        info_path = gomodcache / "cache" / "download" / escaped_module / "@v" / f"{escaped_version}.info"

        if info_path.exists():
            skip_count += 1
            continue

        # Download to get .info file with VCS metadata
        try:
            result = subprocess.run(
                ['go', 'mod', 'download', f'{module_path}@{version}'],
                cwd=source_dir,
                env=env,
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode == 0:
                success_count += 1
            else:
                fail_count += 1
                if "no matching versions" not in result.stderr:
                    print(f"  Warning: Failed to download {module_path}@{version}: {result.stderr.strip()[:100]}")

        except subprocess.TimeoutExpired:
            fail_count += 1
            print(f"  Warning: Timeout downloading {module_path}@{version}")
        except Exception as e:
            fail_count += 1
            print(f"  Warning: Error downloading {module_path}@{version}: {e}")

    print(f"\nDownload results:")
    print(f"  ✓ {success_count} modules downloaded")
    print(f"  ⊙ {skip_count} modules already cached")
    print(f"  ✗ {fail_count} modules failed")
    print(f"  → Total: {len(required_modules)} modules")


def discover_modules(source_dir: Path, gomodcache: Optional[str] = None) -> List[Dict]:
    """
    Phase 1: Discovery

    Let Go download modules to discover correct paths and metadata.
    This is ONLY for discovery - we build from git sources.

    Returns list of modules with:
    - module_path: CORRECT path from filesystem (no /v3 stripping!)
    - version: Module version
    - vcs_url: Git repository URL
    - vcs_hash: Git commit hash
    - vcs_ref: Git reference (tag/branch)
    - timestamp: Commit timestamp
    - subdir: Subdirectory within repo (for submodules)
    """
    global CURRENT_GOMODCACHE
    print("\n" + "=" * 70)
    print("PHASE 1: DISCOVERY - Using Go to discover module metadata")
    print("=" * 70)

    # Create temporary or use provided GOMODCACHE
    if gomodcache:
        temp_cache = Path(gomodcache)
        print(f"Using existing GOMODCACHE: {temp_cache}")
        cleanup_cache = False
    else:
        temp_cache = Path(tempfile.mkdtemp(prefix="go-discover-"))
        print(f"Created temporary cache: {temp_cache}")
        cleanup_cache = True
    CURRENT_GOMODCACHE = str(temp_cache)

    try:
        ensure_path_is_writable(temp_cache)

        # Set up environment for Go
        env = os.environ.copy()
        env['GOMODCACHE'] = str(temp_cache)
        env['GOPROXY'] = 'https://proxy.golang.org'

        print(f"\nDownloading modules to discover metadata...")
        print(f"Source: {source_dir}")

        # Let Go download everything (initial discovery)
        result = subprocess.run(
            ['go', 'mod', 'download'],
            cwd=source_dir,
            env=env,
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            print(f"Warning: go mod download had errors:\n{result.stderr}")
            # Continue anyway - some modules may have been downloaded

        # PRIORITY #2 FIX: Download ALL modules from go.mod (direct + indirect)
        # This replaces the need for fast-fix-module.py by ensuring all
        # transitive dependencies have .info files for discovery
        download_all_required_modules(source_dir, temp_cache)

        # Walk filesystem to discover what Go created
        modules = []
        download_dir = temp_cache / "cache" / "download"

        if not download_dir.exists():
            print(f"Error: Download directory not found: {download_dir}")
            return []

        print(f"\nScanning {download_dir} for modules...")

        for dirpath, _, filenames in os.walk(download_dir):
            path_parts = Path(dirpath).relative_to(download_dir).parts

            # Look for @v directories
            if not path_parts or path_parts[-1] != '@v':
                continue

            # Module path is everything before @v
            module_path = '/'.join(path_parts[:-1])
            module_path = unescape_module_path(module_path)  # Unescape !-encoding

            # Process each .info file
            for filename in filenames:
                if not filename.endswith('.info'):
                    continue

                version = filename[:-5]  # Strip .info extension
                info_path = Path(dirpath) / filename

                try:
                    # Read metadata from .info file
                    with open(info_path) as f:
                        info = json.load(f)

                    # Extract VCS information
                    origin = info.get('Origin', {})
                    vcs_url = origin.get('URL')
                    vcs_hash = origin.get('Hash')
                    vcs_ref = origin.get('Ref', '')
                    subdir = origin.get('Subdir', '')

                    if not vcs_url or not vcs_hash:
                        # Try to refresh cache entry and ask Go directly for metadata.
                        go_mod_download(module_path, version)

                        # Reload .info in case go mod download updated it.
                        try:
                            with open(info_path) as f:
                                info = json.load(f)
                            origin = info.get('Origin', {})
                            vcs_url = origin.get('URL')
                            vcs_hash = origin.get('Hash')
                            vcs_ref = origin.get('Ref', '')
                            subdir = origin.get('Subdir', '')
                        except Exception:
                            pass

                        if not vcs_url or not vcs_hash:
                            go_info = query_module_via_go_list(module_path, version)
                            if go_info:
                                vcs_url = go_info.get('vcs_url')
                                vcs_hash = go_info.get('commit')
                                subdir = go_info.get('subdir', subdir)
                                origin_time = go_info.get('timestamp', '')
                                if origin_time:
                                    info['Time'] = origin_time

                    if not vcs_url or not vcs_hash:
                        print(f"  ⚠️  Skipping {module_path}@{version}: No VCS info")
                        continue

                    overrides = repo_override_candidates(module_path, version)
                    if overrides:
                        vcs_url = overrides[0]

                    # BitBake requires full 40-character commit hashes
                    if len(vcs_hash) != 40:
                        print(f"  ⚠️  Skipping {module_path}@{version}: Short commit hash ({vcs_hash})")
                        continue

                    # PROACTIVE dangling commit detection and correction
                    # Check if commit is BitBake-fetchable BEFORE expensive verification
                    # BitBake's nobranch=1 requires commits to be branch/tag HEADs, not dangling commits
                    if VERIFY_ENABLED and vcs_ref and vcs_ref.startswith("refs/"):
                        if not is_commit_bitbake_fetchable(vcs_url, vcs_hash, vcs_ref):
                            print(f"  ⚠️  DANGLING COMMIT: {module_path}@{version} commit {vcs_hash[:12]} not a branch/tag HEAD")

                            # Try to correct by dereferencing the ref
                            corrected_hash = correct_commit_hash_from_ref(vcs_url, vcs_hash, vcs_ref)
                            if corrected_hash:
                                print(f"      ✓ Corrected hash by dereferencing {vcs_ref}: {vcs_hash[:12]} → {corrected_hash[:12]}")
                                vcs_hash = corrected_hash
                            else:
                                print(f"      ❌ Could not auto-correct dangling commit")
                                # Continue anyway - verification will catch if it's truly unfetchable

                    # Validate commit exists in repository (detect force-pushed tags)
                    # If verification is enabled, check that the commit from .info file
                    # actually exists in the repository. If not, refresh from Go proxy.
                    commit_verified = VERIFY_ENABLED and verify_commit_accessible(vcs_url, vcs_hash, vcs_ref, version, origin_time)

                    # Apply fallback commit if verification used one (for orphaned commits)
                    if commit_verified and VERIFY_ENABLED:
                        vcs_hash = get_actual_commit(vcs_url, vcs_hash)

                    if VERIFY_ENABLED and not commit_verified:
                        print(f"  ⚠️  STALE CACHE: {module_path}@{version} commit {vcs_hash[:12]} not found in {vcs_url}")

                        # Last resort: Try proxy refresh (this shouldn't happen if dangling check worked)
                        corrected_hash = correct_commit_hash_from_ref(vcs_url, vcs_hash, vcs_ref)
                        if corrected_hash:
                            print(f"      ✓ Corrected hash by dereferencing {vcs_ref}: {vcs_hash[:12]} → {corrected_hash[:12]}")
                            vcs_hash = corrected_hash
                            # Verify the corrected hash is accessible
                            if verify_commit_accessible(vcs_url, vcs_hash, vcs_ref, version, origin_time):
                                # Successfully corrected! Continue with this module (skip proxy refresh)
                                commit_verified = True
                            else:
                                print(f"      ❌ Even corrected commit not accessible")

                        # If still not verified after correction attempt, try proxy refresh
                        if not commit_verified:
                            # Check if module is actually needed before attempting refresh
                            if not is_module_actually_needed(module_path, CURRENT_SOURCE_DIR):
                                print(f"      ℹ️  Module not needed by main module (indirect-only), skipping")
                                print(f"      (Verified via 'go mod why {module_path}')")
                                continue

                            print(f"      Attempting to refresh from Go proxy...")

                            # Delete stale .info file to force re-download
                            try:
                                info_path.unlink()
                                print(f"      Deleted stale .info file")
                            except Exception as e:
                                print(f"      Warning: Could not delete .info file: {e}")

                            # Re-download from Go proxy to get current commit
                            try:
                                go_mod_download(module_path, version)

                                # Reload .info file with fresh data
                                if info_path.exists():
                                    with open(info_path) as f:
                                        info = json.load(f)
                                    origin = info.get('Origin', {})
                                    new_vcs_hash = origin.get('Hash')

                                    if new_vcs_hash and new_vcs_hash != vcs_hash:
                                        print(f"      ✓ Refreshed: {vcs_hash[:12]} → {new_vcs_hash[:12]}")
                                        vcs_hash = new_vcs_hash
                                        vcs_ref = origin.get('Ref', vcs_ref)

                                        # Verify new commit exists
                                        if not verify_commit_accessible(vcs_url, vcs_hash, vcs_ref, version, origin.get('Time', '')):
                                            print(f"      ❌ Even refreshed commit not accessible")
                                            # Last resort: check if it's actually needed
                                            if not is_module_actually_needed(module_path, CURRENT_SOURCE_DIR):
                                                print(f"      ℹ️  Module not needed anyway, skipping")
                                                continue
                                            else:
                                                print(f"      ❌ Module IS needed but commit unavailable")
                                                print(f"      This module cannot be built from git sources")
                                                continue
                                    else:
                                        print(f"      ⚠️  Go proxy returned same commit (permanently deleted)")
                                        # Check if it's actually needed
                                        if not is_module_actually_needed(module_path, CURRENT_SOURCE_DIR):
                                            print(f"      ℹ️  Module not needed by main module, skipping")
                                            continue
                                        else:
                                            print(f"      ❌ Module IS needed but commit permanently deleted")
                                            print(f"      Consider using gomod:// fetcher for this module")
                                            continue
                                else:
                                    print(f"      ❌ Re-download failed, skipping module")
                                    continue
                            except Exception as e:
                                print(f"      ❌ Refresh failed: {e}")
                                continue

                    DOWNLOADED_MODULES.add((module_path, version))
                    modules.append({
                        'module_path': module_path,
                        'version': version,
                        'vcs_url': vcs_url,
                        'vcs_hash': vcs_hash,
                        'vcs_ref': vcs_ref,
                        'timestamp': info.get('Time', ''),
                        'subdir': subdir or '',
                    })

                    print(f"  ✓ {module_path}@{version}")

                except Exception as e:
                    print(f"  ✗ Error processing {info_path}: {e}")
                    continue

        print(f"\nDiscovered {len(modules)} modules with VCS info")

        # FIX: Synthesize entries for +incompatible versions that lack VCS data
        # These are pre-v2 versions of modules that later adopted semantic import versioning (/v2, /v3, etc.)
        # The GOMODCACHE has .info files for them but without Origin data (old proxy cache)
        # Strategy: For each versioned module path (e.g., foo/v3), check if a base path version
        # with +incompatible exists in GOMODCACHE and lacks VCS data. If so, synthesize an entry.
        #
        # NOTE (2025-11-28): This code overlaps with Fix #29 in extract-native-modules.py, which
        # now uses derive_vcs_info() to handle +incompatible modules at discovery time. Fix #29
        # is more complete because it handles ALL +incompatible modules directly from their path,
        # not just those with a corresponding /vN version. This code is kept as a fallback for
        # cases where extract-native-modules.py wasn't used (e.g., legacy workflows).
        print("\nSynthesizing entries for +incompatible versions without VCS data...")
        synthesized_count = 0

        # Build a map of module_path -> vcs_url for discovered modules
        module_vcs_map: Dict[str, str] = {}
        for mod in modules:
            module_vcs_map[mod['module_path']] = mod['vcs_url']

        # For each module with a versioned path suffix (/v2, /v3, etc.), check for base path incompatible versions
        for mod in list(modules):  # Iterate over copy since we'll append to modules
            module_path = mod['module_path']
            vcs_url = mod['vcs_url']

            # Check if this module has a version suffix (/v2, /v3, etc.)
            version_match = re.search(r'/v(\d+)$', module_path)
            if not version_match:
                continue

            # Extract base path (without /vN suffix)
            base_path = module_path[:module_path.rfind('/v')]

            # Check if we already discovered the base path
            if base_path in module_vcs_map:
                continue  # Base path already has VCS data, no synthesis needed

            # Look for +incompatible versions of the base path in GOMODCACHE
            # Note: GOMODCACHE uses raw paths as directory names (not escaped)
            base_path_dir = download_dir / base_path / '@v'

            if not base_path_dir.exists():
                continue

            # Scan for .info files with +incompatible versions
            for info_file in base_path_dir.glob('*.info'):
                version = info_file.stem

                if not version.endswith('+incompatible'):
                    continue

                # Read the .info file to check if it lacks VCS data
                try:
                    with open(info_file) as f:
                        info = json.load(f)

                    # If it already has Origin data, skip it
                    if 'Origin' in info and info['Origin'].get('URL') and info['Origin'].get('Hash'):
                        continue

                    # This +incompatible version lacks VCS data - synthesize an entry
                    # Extract the tag name from version (e.g., v2.16.0+incompatible -> v2.16.0)
                    tag_version = version.replace('+incompatible', '')
                    tag_ref = f"refs/tags/{tag_version}"

                    # Use git ls-remote to find the commit for this tag
                    tag_commit = git_ls_remote(vcs_url, tag_ref)

                    if not tag_commit:
                        print(f"  ⚠️  Could not find tag {tag_ref} for {base_path}@{version}")
                        continue

                    # Synthesize a module entry using data from the versioned path
                    synthesized_module = {
                        'module_path': base_path,  # Use BASE path (without /vN)
                        'version': version,
                        'vcs_url': vcs_url,
                        'vcs_hash': tag_commit,
                        'vcs_ref': tag_ref,
                        'timestamp': info.get('Time', ''),
                        'subdir': '',
                    }

                    modules.append(synthesized_module)
                    module_vcs_map[base_path] = vcs_url  # Prevent duplicate synthesis
                    synthesized_count += 1

                    print(f"  ✓ Synthesized {base_path}@{version} (from {module_path} VCS data)")
                    print(f"    VCS: {vcs_url}")
                    print(f"    Commit: {tag_commit[:12]} (tag {tag_version})")

                except Exception as e:
                    print(f"  ⚠️  Error synthesizing {base_path}@{version}: {e}")
                    continue

        if synthesized_count > 0:
            print(f"\nSynthesized {synthesized_count} +incompatible module entries")
        else:
            print("No +incompatible versions needed synthesis")

        print(f"\nTotal modules after synthesis: {len(modules)}")
        return modules

    finally:
        # Defer cleanup of temporary caches until the end of execution
        if cleanup_cache and temp_cache.exists():
            TEMP_GOMODCACHES.append(temp_cache)

# =============================================================================
# Phase 2: Recipe Generation
# =============================================================================

def generate_recipe(modules: List[Dict], source_dir: Path, output_dir: Optional[Path],
                   git_repo: str, git_ref: str, validate_only: bool = False,
                   debug_limit: Optional[int] = None, skip_verify: bool = False,
                   verify_jobs: int = 10, exclude_modules: Optional[List[str]] = None) -> bool:
    """
    Phase 2: Recipe Generation

    Generate BitBake recipe with git:// SRC_URI entries.
    No file:// entries - we'll build cache from git during do_create_module_cache.

    Creates:
    - go-mod-git.inc: SRC_URI with git:// entries
    - go-mod-cache.inc: BitBake task to build module cache
    """
    print("\n" + "=" * 70)
    phase_label = "VALIDATION" if validate_only else "RECIPE GENERATION"
    print(f"PHASE 2: {phase_label} - {('commit verification' if validate_only else 'Creating BitBake recipe files')}")
    print("=" * 70)

    src_uri_entries = []
    modules_data = []
    vcs_repos: Dict[str, Dict] = {}

    def repo_key_for_url(url: str) -> str:
        return hashlib.sha256(f"git3:{url}".encode()).hexdigest()

    def commit_cache_key(repo_key: str, commit: str) -> str:
        return hashlib.sha256(f"{repo_key}:{commit}".encode()).hexdigest()

    unresolved_commits: List[Tuple[str, str, str, str, str]] = []

    # Filter out excluded modules (e.g., deleted upstream repos that must use gomod://)
    if exclude_modules:
        before_count = len(modules)
        excluded_prefixes = [e.strip() for e in exclude_modules]
        modules = [m for m in modules if not any(
            m.get('module_path', '').startswith(prefix) for prefix in excluded_prefixes
        )]
        excluded_count = before_count - len(modules)
        if excluded_count:
            print(f"\n⚙️  Excluded {excluded_count} modules matching: {', '.join(excluded_prefixes)}")

    total_modules = len(modules)
    if debug_limit is not None:
        print(f"\n⚙️  Debug limit active: validating first {debug_limit} modules (total list size {total_modules})")

    if skip_verify:
        print(f"\n⚙️  Skipping verification (--skip-verify enabled)")

    # First pass: Build repo structure without verification
    for index, module in enumerate(modules, start=1):
        vcs_url = module['vcs_url']
        commit_hash = module['vcs_hash']

        repo_key = repo_key_for_url(vcs_url)
        repo_info = vcs_repos.setdefault(
            repo_key,
            {
                'url': vcs_url,
                'commits': {},  # commit hash -> commit metadata
            },
        )

        if commit_hash not in repo_info['commits']:
            commit_sha = commit_cache_key(repo_key, commit_hash)
            repo_info['commits'][commit_hash] = {
                'commit_sha': commit_sha,
                'modules': [],
            }
        else:
            commit_sha = repo_info['commits'][commit_hash]['commit_sha']

        # Trust the ref_hint from discovery - it will be validated/corrected during
        # the verification pass if needed (e.g., force-pushed tags are auto-corrected)
        # BUT: for pseudo-versions, Go's Origin.Ref is the "nearest tag" used to derive
        # the pseudo-version, NOT a tag that points to this commit. Using it as a tag=
        # in SRC_URI causes BitBake to resolve the tag to a different commit and fail.
        ref_hint = module.get('vcs_ref', '')
        version = module.get('version', '')
        if ref_hint and parse_pseudo_version_tag(version):
            # Pseudo-version: the vcs_ref is the base tag, not a ref pointing to this commit
            ref_hint = ''

        entry = repo_info['commits'][commit_hash]
        entry['modules'].append(module)
        if ref_hint:
            entry['ref_hint'] = ref_hint

        module['repo_key'] = repo_key
        module['commit_sha'] = commit_sha

    # Second pass: Verify commits (parallel or sequential) with auto-correction
    # PHASE MERGE: This now includes force-pushed tag detection and auto-correction
    global VERIFY_CORRECTIONS_APPLIED
    if not skip_verify:
        print(f"\n⚙️  Verifying {total_modules} commits with {verify_jobs} parallel jobs")
        corrected_modules = []  # Track corrections for reporting

        def verify_module(module_info):
            index, module = module_info
            vcs_url = module['vcs_url']
            commit_hash = module['vcs_hash']
            ref_hint = module.get('vcs_ref', '')
            # For pseudo-versions, vcs_ref is the nearest tag, not a ref pointing to this commit
            if ref_hint and parse_pseudo_version_tag(module.get('version', '')):
                ref_hint = ''

            print(f"  • verifying [{index}/{total_modules}] {module['module_path']}@{module['version']} -> {commit_hash[:12]}")

            # Verify commit is accessible
            if not verify_commit_accessible(vcs_url, commit_hash, ref_hint, module.get('version', ''), module.get('timestamp', '')):
                # PHASE MERGE: If verification fails and we have a ref, try auto-correction
                if ref_hint and ref_hint.startswith("refs/"):
                    corrected_hash = correct_commit_hash_from_ref(vcs_url, commit_hash, ref_hint)
                    if corrected_hash and corrected_hash != commit_hash:
                        print(f"    ✓ Auto-corrected: {commit_hash[:12]} → {corrected_hash[:12]} (force-pushed tag)")
                        module['vcs_hash'] = corrected_hash

                        # Update repo_info dict to use the new hash as key
                        repo_key = module['repo_key']
                        if commit_hash in vcs_repos[repo_key]['commits']:
                            # Move the entry from old hash to new hash
                            vcs_repos[repo_key]['commits'][corrected_hash] = vcs_repos[repo_key]['commits'].pop(commit_hash)

                        return ('corrected', module['module_path'], module['version'], commit_hash, corrected_hash)
                    else:
                        # Could not correct - treat as failure
                        return ('failed', module['module_path'], module['version'], commit_hash, vcs_url, ref_hint)
                else:
                    # No ref to dereference - genuine failure
                    return ('failed', module['module_path'], module['version'], commit_hash, vcs_url, ref_hint)
            else:
                # Verification succeeded - apply fallback commit if one was used
                actual_hash = get_actual_commit(vcs_url, commit_hash)
                if actual_hash != commit_hash:
                    print(f"    ✓ Applied fallback: {commit_hash[:12]} → {actual_hash[:12]} (orphaned commit)")
                    module['vcs_hash'] = actual_hash

                    # Update repo_info dict to use the new hash as key
                    repo_key = module['repo_key']
                    if commit_hash in vcs_repos[repo_key]['commits']:
                        # Move the entry from old hash to new hash
                        vcs_repos[repo_key]['commits'][actual_hash] = vcs_repos[repo_key]['commits'].pop(commit_hash)

                    return ('corrected', module['module_path'], module['version'], commit_hash, actual_hash)
            return None

        if verify_jobs > 0:
            # Parallel verification
            with concurrent.futures.ThreadPoolExecutor(max_workers=verify_jobs) as executor:
                results = list(executor.map(verify_module, enumerate(modules, start=1)))
        else:
            # Sequential verification (--verify-jobs=0)
            results = []
            for index, module in enumerate(modules, start=1):
                result = verify_module((index, module))
                if result is not None:
                    results.append(result)

                # Save verification cache every 50 modules
                if index % 50 == 0:
                    save_verify_commit_cache(force=True)
                    print(f"  💾 Saved verification cache at {index}/{total_modules}")

        # Separate corrected vs failed results
        corrected_results = [r for r in results if r and r[0] == 'corrected']
        failed_results = [r for r in results if r and r[0] == 'failed']

        # Apply corrections back to modules list (needed for parallel execution)
        if corrected_results:
            VERIFY_CORRECTIONS_APPLIED = True
            print(f"\n✓ Auto-corrected {len(corrected_results)} force-pushed tags:")
            for _, module_path, version, old_hash, new_hash in corrected_results:
                print(f"   • {module_path}@{version}: {old_hash[:12]} → {new_hash[:12]}")

                # Find and update the module in the main list
                for module in modules:
                    if module['module_path'] == module_path and module['version'] == version:
                        module['vcs_hash'] = new_hash

                        # Also update the vcs_repos dict
                        repo_key = module['repo_key']
                        if old_hash in vcs_repos[repo_key]['commits']:
                            vcs_repos[repo_key]['commits'][new_hash] = vcs_repos[repo_key]['commits'].pop(old_hash)
                        break
    else:
        # Verification skipped - no failed results
        failed_results = []

    print(f"\nFound {len(vcs_repos)} unique git repositories")
    print(f"Supporting {len(modules)} modules")

    if failed_results:
        print("\n❌ Unable to verify the following module commits against their repositories:")
        for _, module_path, version, commit_hash, vcs_url, ref_hint in failed_results:
            print(f"\n   - {module_path}@{version} ({commit_hash})")
            hint = f" {ref_hint}" if ref_hint else ""
            print(f"     try: git fetch --depth=1 {vcs_url}{hint} {commit_hash}")
            print()
            print(f"     Option 1: Exclude from VCS and fetch via Go module proxy instead.")
            print(f"               Add to your recipe (.bb):")
            print(f'         SRC_URI += "gomod://{module_path};version={version};sha256sum=<run bitbake -c fetch to get>"')
            print(f'         GO_MOD_VCS_EXCLUDE += "{module_path}"')
            print()
            print(f"     Option 2: Same result, but for direct oe-go-mod-fetcher.py invocation.")
            print(f"               Run before generation:")
            print(f"         python3 oe-go-mod-fetcher.py --inject-commit '{vcs_url} {commit_hash}' \\")
            print(f"           --set-repo {module_path}@{version} {vcs_url} \\")
            print(f"           --discovered-modules <modules.json> --git-repo <repo> --git-ref <ref> --recipedir <dir>")
        print("\nAborting to prevent emitting invalid SRCREVs.")
        return False

    if validate_only:
        print("\n✅ Validation complete - all commits are reachable upstream")
        return True

    if output_dir is None:
        print("❌ Internal error: output directory missing for recipe generation")
        return False

    # Generate SRC_URI entries for each repo/commit combination
    for repo_key, repo_info in vcs_repos.items():
        git_url = repo_info['url']

        if git_url.startswith('https://'):
            git_url_bb = 'git://' + git_url[8:]
            protocol = 'https'
        elif git_url.startswith('http://'):
            git_url_bb = 'git://' + git_url[7:]
            protocol = 'http'
        else:
            git_url_bb = git_url
            protocol = 'https'

        for idx, (commit_hash, commit_info) in enumerate(sorted(repo_info['commits'].items())):
            fetch_name = f"git_{repo_key[:8]}_{idx}"
            destsuffix = f"vcs_cache/{commit_info['commit_sha']}"

            # Use branch name from ref_hint when available (more reliable than nobranch=1)
            # ref_hint is like "refs/tags/v1.9.3" or "refs/heads/main"
            ref_hint = commit_info.get('ref_hint', '')
            if ref_hint:
                shallow_param = ';shallow=1'
                # For tags, use nobranch=1 since the commit may not be on a branch head
                # For branches, use the branch name directly
                if ref_hint.startswith('refs/tags/'):
                    # Tags: BitBake can fetch tagged commits with nobranch=1
                    # Add tag= so shallow clones include this tag (with BB_GIT_SHALLOW=1 in recipe)
                    tag_name = ref_hint[10:]  # Strip "refs/tags/"
                    branch_param = f';nobranch=1;tag={tag_name}'
                elif ref_hint.startswith('refs/heads/'):
                    # Branches: use the actual branch name
                    branch_name = ref_hint[11:]  # Strip "refs/heads/"
                    branch_param = f';branch={branch_name}'
                else:
                    branch_param = ';nobranch=1'
            else:
                # For pseudo-versions (no ref_hint), check if we detected a branch
                detected_branch = VERIFY_DETECTED_BRANCHES.get((git_url, commit_hash))
                if detected_branch:
                    # Use the detected branch name instead of nobranch=1
                    shallow_param = ''
                    branch_param = f';branch={detected_branch}'
                    print(f"    Using detected branch: {detected_branch} for {commit_hash[:12]}")
                else:
                    # No ref and no detected branch - use nobranch=1
                    # This should only happen for genuine orphaned commits that couldn't be fixed
                    shallow_param = ''
                    branch_param = ';nobranch=1'

            src_uri_entries.append(
                f'{git_url_bb};protocol={protocol}{branch_param}{shallow_param};'
                f'rev={commit_hash};'
                f'name={fetch_name};'
                f'destsuffix={destsuffix}'
            )

            commit_info['fetch_name'] = fetch_name
            commit_info['destsuffix'] = destsuffix

            if len(repo_info['commits']) == 1:
                print(f"  {fetch_name}: {repo_info['url'][:60]}...")
            else:
                print(f"  {fetch_name}: {repo_info['url'][:60]}... (commit {commit_hash[:12]})")

    # Prepare modules data for do_create_module_cache
    for module in modules:
        repo_key = module['repo_key']
        commit_hash = module['vcs_hash']
        commit_info = vcs_repos[repo_key]['commits'][commit_hash]

        update_metadata_cache(
            module['module_path'],
            module['version'],
            module['vcs_url'],
            module['vcs_hash'],
            module.get('timestamp', ''),
            module.get('subdir', ''),
            module.get('vcs_ref', ''),
            dirty=True,
        )

        # DEBUG: Track server/v3 module
        if 'server/v3' in module['module_path']:
            print(f"\n🔍 DEBUG server/v3: Adding to modules_data")
            print(f"   module_path: {module['module_path']}")
            print(f"   subdir: '{module.get('subdir', '')}' (from module dict)")
            print(f"   timestamp: {module['timestamp']}")
            print(f"   vcs_hash: {module['vcs_hash']}")

        modules_data.append({
            'module': module['module_path'],
            'version': module['version'],
            'vcs_hash': commit_info['commit_sha'],
            'timestamp': module['timestamp'],
            'subdir': module.get('subdir', ''),
            'vcs_ref': module.get('vcs_ref', ''),
        })

    # Write go-mod-git.inc
    git_inc_path = output_dir / "go-mod-git.inc"
    print(f"\nWriting {git_inc_path}")

    with open(git_inc_path, 'w') as f:
        f.write("# Generated by oe-go-mod-fetcher.py v" + VERSION + "\n")
        f.write("# Git repositories for Go module dependencies\n\n")
        for entry in src_uri_entries:
            f.write(f'SRC_URI += "{entry}"\n')
        f.write('\n')

        # Note: BB_GIT_SHALLOW_EXTRA_REFS is NOT used here because those refs must be
        # present in ALL repositories, which isn't the case for module dependencies.
        # Instead, we use tag= in individual SRC_URI entries when the ref is a tag.
        # The recipe should set BB_GIT_SHALLOW = "1" to enable shallow clones globally.

        # Note: SRCREV_* variables are not needed since rev= is embedded directly in SRC_URI

    # Write go-mod-cache.inc
    cache_inc_path = output_dir / "go-mod-cache.inc"
    print(f"Writing {cache_inc_path}")

    with open(cache_inc_path, 'w') as f:
        f.write("# Generated by oe-go-mod-fetcher.py v" + VERSION + "\n")
        f.write("# Module cache data for Go dependencies\n")
        f.write("#\n")
        f.write("# This file contains recipe-specific module metadata.\n")
        f.write("# The task implementations are in go-mod-vcs.bbclass.\n\n")

        # Inherit the bbclass that provides the task implementations
        f.write("inherit go-mod-vcs\n\n")

        # Write modules data as JSON - one module per line for readability
        f.write("# Module metadata for cache building (one module per line)\n")
        f.write("GO_MODULE_CACHE_DATA = '[\\\n")
        for i, mod in enumerate(modules_data):
            line = json.dumps(mod, separators=(',', ':'))
            if i < len(modules_data) - 1:
                f.write(f"{line},\\\n")
            else:
                f.write(f"{line}\\\n")
        f.write("]'\n")

    print(f"\n✅ Generated recipe files:")
    print(f"   {git_inc_path}")
    print(f"   {cache_inc_path}")
    print(f"\nTo use these files, add to your recipe:")
    print(f"   require go-mod-git.inc")
    print(f"   require go-mod-cache.inc")
    print(f"   require go-mod-licenses.inc  # if --scan-licenses was used")

    return True

# =============================================================================
# Discovered Module Loading (Bootstrap Strategy)
# =============================================================================

def load_discovered_modules(discovered_modules_path: Path) -> Optional[List[Dict]]:
    """
    Load pre-discovered module metadata from BitBake discovery build.

    This implements the bootstrap strategy where a BitBake discovery build has
    already run 'go mod download' (via do_discover_modules task) and
    extract-native-modules.py has extracted complete metadata from the GOMODCACHE.

    Args:
        discovered_modules_path: Path to JSON file with module metadata

    Returns:
        List of module dicts with complete VCS info, or None if load fails
    """
    if not discovered_modules_path.exists():
        print(f"❌ Discovered modules file not found: {discovered_modules_path}")
        return None

    try:
        with open(discovered_modules_path) as f:
            modules = json.load(f)

        if not isinstance(modules, list):
            print(f"❌ Invalid discovered modules file format (expected list, got {type(modules).__name__})")
            return None

        print(f"✓ Loaded {len(modules)} modules from discovery metadata")
        print(f"  File: {discovered_modules_path}")

        # Validate module format
        required_fields = ['module_path', 'version', 'vcs_url', 'vcs_hash']
        for i, module in enumerate(modules):
            if not isinstance(module, dict):
                print(f"❌ Module {i} is not a dict: {module}")
                return None
            for field in required_fields:
                if field not in module:
                    print(f"❌ Module {i} missing required field '{field}': {module.get('module_path', '<unknown>')}")
                    return None

        # Show statistics
        unique_repos = len(set(m['vcs_url'] for m in modules))
        with_subdirs = sum(1 for m in modules if m.get('subdir'))

        print(f"\nDiscovery metadata summary:")
        print(f"  Modules: {len(modules)}")
        print(f"  Unique repositories: {unique_repos}")
        print(f"  Multi-module repos: {with_subdirs} modules have subdirs")

        # Expand 12-char short hashes to full 40-char hashes.
        # Pseudo-versions like v0.0.0-20161002113705-648efa622239 only contain
        # 12 chars of the commit hash. BitBake's git fetcher needs full 40-char.
        short_hash_modules = [m for m in modules if len(m.get('vcs_hash', '')) == 12]
        if short_hash_modules:
            print(f"\n⚙️  Expanding {len(short_hash_modules)} short hashes to full 40-char...")
            expanded = 0
            failed = 0
            for i, module in enumerate(short_hash_modules):
                if (i + 1) % 20 == 0 or i == 0:
                    print(f"  Progress: {i + 1}/{len(short_hash_modules)}...", end='\r', flush=True)

                version = module.get('version', '')
                vcs_url = module['vcs_url']
                short_hash = module['vcs_hash']

                # Parse pseudo-version to get timestamp
                pseudo_info = parse_pseudo_version_tag(version.split('+')[0])
                if pseudo_info:
                    timestamp_str, _ = pseudo_info
                    full_hash = resolve_pseudo_version_commit(
                        vcs_url, timestamp_str, short_hash,
                        clone_cache_dir=CLONE_CACHE_DIR
                    )
                    if full_hash and len(full_hash) == 40:
                        module['vcs_hash'] = full_hash
                        expanded += 1
                    else:
                        failed += 1
                        if VERBOSE_MODE:
                            print(f"\n  ⚠️  Could not expand: {module['module_path']}@{version}")
                else:
                    failed += 1

            print(f"  Expanded {expanded} short hashes, {failed} failed                    ")

        # Filter out modules with empty vcs_hash - these are typically pre-Go 1.18
        # modules lacking Origin metadata (e.g. pre-release pseudo-versions) that
        # cannot be fetched from git. They are usually transitive dependencies that
        # aren't actually needed by the build.
        empty_hash_modules = [m for m in modules if not m.get('vcs_hash')]
        if empty_hash_modules:
            print(f"\n⚠️  Filtering out {len(empty_hash_modules)} modules with empty vcs_hash:")
            for m in empty_hash_modules:
                print(f"   - {m['module_path']}@{m['version']}")
            modules = [m for m in modules if m.get('vcs_hash')]
            print(f"  Remaining modules: {len(modules)}")

        return modules

    except json.JSONDecodeError as e:
        print(f"❌ Failed to parse discovered modules JSON: {e}")
        return None
    except Exception as e:
        print(f"❌ Error loading discovered modules: {e}")
        return None

# =============================================================================
# License Scanning
# =============================================================================

LICENSE_FILE_PATTERNS = [
    '*LICEN[CS]E*', 'COPYING*', '*[Ll]icense*', 'LEGAL*', '[Ll]egal*',
    '*GPL*', 'README.lic*', 'COPYRIGHT*', '[Cc]opyright*', 'e[dp]l-v10',
]

LICENSE_SKIP_EXTENSIONS = ('.html', '.js', '.json', '.svg', '.ts', '.go', '.sh')


def _squashspaces(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def _crunch_license_text(text: str) -> Optional[str]:
    """Compute crunched MD5 of license text (same algorithm as OE-core)."""
    license_title_re = re.compile(
        r'^#*\(? *(This is )?([Tt]he )?.{0,15} ?[Ll]icen[sc]e( \(.{1,10}\))?\)?[:\.]? ?#*$')
    license_statement_re = re.compile(
        r'^((This (project|software)|.{1,10}) is( free software)? (released|licen[sc]ed)'
        r'|(Released|Licen[cs]ed)) under the .{1,10} [Ll]icen[sc]e:?$')
    copyright_re = re.compile(
        r'^ *[#\*]* *(Modified work |MIT LICENSED )?Copyright ?(\([cC]\))? .*$')
    disclaimer_re = re.compile(r'^ *\*? ?All [Rr]ights [Rr]eserved\.$')
    email_re = re.compile(r'^.*<[\w\.-]*@[\w\.\-]*>$')
    header_re = re.compile(r'^(\/\**!?)? ?[\-=\*]* ?(\*\/)?$')
    tag_re = re.compile(r'^ *@?\(?([Ll]icense|MIT)\)?$')
    url_re = re.compile(r'^ *[#\*]* *https?:\/\/[\w\.\/\-]+$')

    lictext = []
    for line in text.splitlines():
        if copyright_re.match(line):
            continue
        if disclaimer_re.match(line):
            continue
        if email_re.match(line):
            continue
        if header_re.match(line):
            continue
        if tag_re.match(line):
            continue
        if url_re.match(line):
            continue
        if license_title_re.match(line):
            continue
        if license_statement_re.match(line):
            continue
        line = line.replace('*', '').replace('#', '')
        line = line.replace('sub-license', 'sublicense')
        line = _squashspaces(line)
        line = (line.replace(u"\u2018", "'").replace(u"\u2019", "'")
                .replace(u"\u201c", "'").replace(u"\u201d", "'")
                .replace('"', "'").replace('`', "'"))
        line = line.replace("{", "[").replace("}", "]")
        if line:
            lictext.append(line)

    m = hashlib.md5()
    try:
        m.update(' '.join(lictext).encode('utf-8'))
        return m.hexdigest()
    except UnicodeEncodeError:
        return None


def _md5_bytes(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


def _build_license_db_from_dir(common_license_dir: str) -> Dict[str, str]:
    """Build MD5->SPDX map by scanning a common-licenses directory."""
    md5_to_spdx = {}
    for fn in os.listdir(common_license_dir):
        path = os.path.join(common_license_dir, fn)
        if not os.path.isfile(path):
            continue
        with open(path, 'rb') as f:
            data = f.read()
        exact_md5 = _md5_bytes(data)
        md5_to_spdx[exact_md5] = fn
        try:
            text = data.decode('utf-8', errors='surrogateescape')
        except Exception:
            continue
        crunched = _crunch_license_text(text)
        if crunched:
            md5_to_spdx[crunched] = fn
    return md5_to_spdx


def _load_license_db_from_csv(csv_path: str) -> Dict[str, str]:
    """Load MD5->SPDX map from bundled CSV."""
    md5_to_spdx = {}
    with open(csv_path, newline='') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split(',', 2)
            if len(parts) < 3:
                continue
            exact_md5, crunched_md5, spdx_id = parts
            md5_to_spdx[exact_md5] = spdx_id
            if crunched_md5:
                md5_to_spdx[crunched_md5] = spdx_id
    return md5_to_spdx


def _find_common_license_dir() -> Optional[str]:
    """Auto-detect common-licenses dir by walking up from script location."""
    script_dir = Path(__file__).resolve().parent
    # Walk up looking for meta/files/common-licenses
    for parent in [script_dir] + list(script_dir.parents):
        candidate = parent / 'meta' / 'files' / 'common-licenses'
        if candidate.is_dir():
            return str(candidate)
    return None


def _resolve_license_db(common_license_dir: Optional[str]) -> Dict[str, str]:
    """Resolve the license hash database using the priority order."""
    # Option 1: Explicit --common-license-dir
    if common_license_dir and os.path.isdir(common_license_dir):
        db = _build_license_db_from_dir(common_license_dir)
        print(f"  License DB: {len(db)} hashes from {common_license_dir}")
        return db

    # Option 2: Auto-detect from poky tree
    auto_dir = _find_common_license_dir()
    if auto_dir:
        db = _build_license_db_from_dir(auto_dir)
        print(f"  License DB: {len(db)} hashes (auto-detected {auto_dir})")
        return db

    # Option 3: Bundled CSV
    csv_path = Path(__file__).resolve().parent / 'data' / 'license-hashes.csv'
    if csv_path.exists():
        db = _load_license_db_from_csv(str(csv_path))
        print(f"  License DB: {len(db)} hashes from bundled CSV")
        print(f"  WARNING: Using bundled CSV - may not include custom or recently-added licenses")
        return db

    print("  WARNING: No license database found - license scanning will mark all as Unknown")
    return {}


def _is_license_file(filename: str) -> bool:
    """Check if filename matches license file patterns."""
    if filename.endswith(LICENSE_SKIP_EXTENSIONS):
        return False
    for pattern in LICENSE_FILE_PATTERNS:
        if fnmatch.fnmatch(filename, pattern):
            return True
    return False


def _go_module_case_encode(path: str) -> str:
    """Encode a Go module path for filesystem: uppercase -> !lowercase."""
    return re.sub(r'([A-Z])', lambda m: '!' + m.group(1).lower(), path)


def _scan_licenses_from_zip(zip_path: str, license_db: Dict[str, str]
                            ) -> List[Tuple[str, str, str]]:
    """
    Scan a Go module zip for license files.

    Returns list of (spdx_name, relative_path, md5_hash) tuples.
    relative_path is within the module root (no module@version prefix).
    """
    results = []
    try:
        with zipfile.ZipFile(zip_path, 'r') as zf:
            # Determine the prefix (module@version/) from the first entry
            prefix = None
            for name in zf.namelist():
                at_idx = name.find('@')
                if at_idx >= 0:
                    slash_idx = name.find('/', at_idx)
                    if slash_idx >= 0:
                        prefix = name[:slash_idx + 1]
                        break
            if not prefix:
                return results

            for info in zf.infolist():
                if info.is_dir():
                    continue
                if not info.filename.startswith(prefix):
                    continue
                rel_path = info.filename[len(prefix):]
                if not rel_path:
                    continue
                basename = os.path.basename(rel_path)
                if not _is_license_file(basename):
                    continue
                # Only scan top-level license files (not in subdirectories)
                # to match OE-core's first_only=True behavior
                if '/' in rel_path:
                    continue

                data = zf.read(info.filename)
                md5 = _md5_bytes(data)
                spdx = license_db.get(md5)
                if not spdx:
                    try:
                        text = data.decode('utf-8', errors='surrogateescape')
                    except Exception:
                        text = ''
                    crunched = _crunch_license_text(text)
                    if crunched:
                        spdx = license_db.get(crunched)
                if not spdx:
                    spdx = 'Unknown'
                results.append((spdx, rel_path, md5))
    except (zipfile.BadZipFile, OSError) as e:
        print(f"  WARNING: Could not read zip {zip_path}: {e}")
    return results


def _find_module_zip(discovery_cache: str, module_path: str, version: str) -> Optional[str]:
    """Find the .zip for a module in the discovery cache."""
    encoded_path = _go_module_case_encode(module_path)
    zip_path = os.path.join(
        discovery_cache, 'cache', 'download',
        encoded_path, '@v', f'{version}.zip'
    )
    if os.path.isfile(zip_path):
        return zip_path
    return None


def scan_module_licenses(modules: List[Dict], discovery_cache: str,
                         license_db: Dict[str, str]) -> Dict[str, Tuple[str, str, str]]:
    """
    Scan all modules for licenses using their discovery cache zips.

    Returns dict mapping "module_path@version" to (spdx_name, license_file, md5).
    Only the first license file per module (matching OE-core behavior).
    """
    results = {}
    scanned = 0
    no_zip = 0
    unknown = 0

    for module in modules:
        module_path = module['module_path']
        version = module['version']
        key = f"{module_path}@{version}"

        zip_path = _find_module_zip(discovery_cache, module_path, version)
        if not zip_path:
            no_zip += 1
            continue

        licenses = _scan_licenses_from_zip(zip_path, license_db)
        if licenses:
            # Take first match (sorted by path for determinism)
            licenses.sort(key=lambda x: x[1])
            spdx, rel_path, md5 = licenses[0]
            results[key] = (spdx, rel_path, md5)
            if spdx == 'Unknown':
                unknown += 1
        scanned += 1

    print(f"\n  License scan: {len(results)} modules with licenses, "
          f"{no_zip} missing zips, {unknown} unknown")
    return results


def _fold_uri(uri: str) -> str:
    """Fold URI for sorting (same as OE-core go-mod-update-modules)."""
    return uri.replace(';', ' ').replace('/', '!')


def _tidy_licenses(licenses: Set[str]) -> List[str]:
    """Sort and deduplicate license names."""
    return sorted(licenses - {'Unknown'}, key=str.casefold)


def write_license_inc(output_dir: Path, license_results: Dict[str, Tuple[str, str, str]]) -> Path:
    """
    Write go-mod-licenses.inc with LICENSE and LIC_FILES_CHKSUM.

    Args:
        output_dir: Recipe directory for output
        license_results: Dict mapping "module@version" to (spdx, file, md5)

    Returns:
        Path to generated file
    """
    import urllib.parse

    licenses = set()
    lic_entries = []

    for mod_ver, (spdx, lic_file, md5) in license_results.items():
        licenses.add(spdx)
        # Build path matching OE-core format: pkg/mod/<module@version>/<file>
        lic_path = f"pkg/mod/{mod_ver}/{lic_file}"
        encoded_spdx = urllib.parse.quote_plus(spdx)
        lic_entries.append(f"file://{lic_path};md5={md5};spdx={encoded_spdx}")

    tidy = _tidy_licenses(licenses)

    inc_path = output_dir / "go-mod-licenses.inc"
    with open(inc_path, 'w') as f:
        f.write(f"# Generated by oe-go-mod-fetcher.py v{VERSION}\n")
        f.write("#\n")
        f.write("# Do not modify by hand. Regenerate with:\n")
        f.write("#   bitbake <recipe> -c discover_and_generate\n\n")
        if tidy:
            f.write(f'LICENSE += "& {" & ".join(tidy)}"\n\n')
        else:
            f.write('# No known licenses found\n\n')
        f.write('LIC_FILES_CHKSUM += "\\\n')
        for entry in sorted(lic_entries, key=_fold_uri):
            f.write(f'    {entry} \\\n')
        f.write('"\n')

    unknown_count = sum(1 for s, _, _ in license_results.values() if s == 'Unknown')
    print(f"\n  Wrote {inc_path}")
    print(f"  Licenses: {', '.join(tidy) if tidy else 'none'}")
    if unknown_count:
        print(f"  WARNING: {unknown_count} modules with Unknown license")

    return inc_path


# =============================================================================
# Main Entry Point
# =============================================================================

def main():
    global LOG_PATH, CURRENT_GOMODCACHE
    parser = argparse.ArgumentParser(
        description=f"Generate BitBake recipes for Go modules using hybrid approach (v{VERSION})",
        epilog="""
This tool uses a 3-phase hybrid approach:
  1. Discovery: Run 'go mod download' to get correct module paths
  2. Recipe Generation: Create git:// SRC_URI entries for BitBake
  3. Cache Building: Build module cache from git during do_create_module_cache

Persistent Caches:
  The generator maintains caches in the data/ subdirectory:
  - data/module-cache.json: Module metadata (VCS URL, timestamp, subdir, etc.)
  - data/ls-remote-cache.json: Git ls-remote results
  - data/vanity-url-cache.json: Vanity import path resolution
  - data/verify-cache.json: Commit verification status

  These caches speed up regeneration but may need cleaning when:
  - Derivation logic changes (e.g., subdir calculation fixes)
  - Cached data becomes stale or incorrect

  Use --clean-cache to remove metadata cache before regeneration.
  Use --clean-ls-remote-cache to remove both caches (slower, but fully fresh).

License Scanning:
  Use --scan-licenses to generate go-mod-licenses.inc with LICENSE and
  LIC_FILES_CHKSUM for all Go module dependencies. License files are
  detected using OE-core's glob patterns and matched against known SPDX
  licenses via MD5 + crunched MD5 hashing.

  The license hash database is resolved in order:
  1. --common-license-dir <path> (explicit)
  2. Auto-detect from poky tree (walk up from script location)
  3. Bundled data/license-hashes.csv (offline fallback)

Examples:
  # Normal regeneration (fast, uses caches)
  %(prog)s --recipedir /path/to/recipe/output

  # With license scanning (requires discovery cache with .zip files)
  %(prog)s --recipedir /path/to/recipe/output \\
    --scan-licenses --discovery-cache /path/to/discovery/cache

  # Clean metadata cache (e.g., after fixing subdir derivation)
  %(prog)s --recipedir /path/to/recipe/output --clean-cache

  # Fully clean regeneration (slow, calls git ls-remote for everything)
  %(prog)s --recipedir /path/to/recipe/output --clean-ls-remote-cache
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        "--recipedir",
        help="Output directory for generated .inc files (required unless running with --validate/--dry-run/--clean-only)"
    )

    parser.add_argument(
        "--gomodcache",
        help="Directory to use for Go module cache (for discovery phase)"
    )

    parser.add_argument(
        "--cache-dir",
        help="Directory to store JSON metadata caches (default: scripts/data)"
    )

    parser.add_argument(
        "--clone-cache-dir",
        help="Directory to cache cloned git repositories (default: scripts/.cache/repos)"
    )

    parser.add_argument(
        "--source-dir",
        help="Source directory containing go.mod (default: current directory)"
    )

    parser.add_argument(
        "--git-repo",
        help="Git repository URL (for documentation purposes)"
    )

    parser.add_argument(
        "--git-ref",
        help="Git reference (for documentation purposes)"
    )

    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Verbose output"
    )

    parser.add_argument(
        "--clean-cache",
        action="store_true",
        help="Clear metadata cache before regeneration (useful when derivation logic changes)"
    )

    parser.add_argument(
        "--clean-ls-remote-cache",
        action="store_true",
        help="Clear git ls-remote cache in addition to metadata cache (implies --clean-cache)"
    )

    parser.add_argument(
        "--skip-legacy-module-cache",
        action="store_true",
        help="Skip importing legacy module metadata from module_cache_task.inc"
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Execute cache mutations without discovery/generation"
    )

    parser.add_argument(
        "--clean-gomodcache",
        action="store_true",
        help="Clean stale .info files in GOMODCACHE that lack VCS metadata (fixes 'module lookup disabled' errors)"
    )

    parser.add_argument(
        "--validate",
        action="store_true",
        help="Validate module commits without emitting recipe files"
    )

    parser.add_argument(
        "--validate-only",
        action="store_true",
        help=argparse.SUPPRESS
    )

    parser.add_argument(
        "--skip-verify",
        action="store_true",
        help="Skip commit verification (trust cached verify results, much faster)"
    )

    parser.add_argument(
        "--verify-jobs",
        type=int,
        default=10,
        metavar="N",
        help="Number of parallel verification jobs (default: 10, 0=sequential)"
    )

    parser.add_argument(
        "--verify-cached",
        action="store_true",
        help="Verify commits in GOMODCACHE .info files still exist in repositories (detects force-pushed tags)"
    )

    parser.add_argument(
        "--verify-cache-max-age",
        type=int,
        default=30,
        metavar="DAYS",
        help="Re-verify cached commits older than this many days (default: 30, 0=always verify)"
    )

    parser.add_argument(
        "--debug-limit",
        type=int,
        help="Process at most N modules during validation/generation (debug only)"
    )

    parser.add_argument(
        "--inject-commit",
        metavar=("REPO", "COMMIT"),
        nargs=2,
        action="append",
        help="Mark a repo+commit pair as already verified (skips network check)"
    )

    parser.add_argument(
        "--clear-commit",
        metavar=("REPO", "COMMIT"),
        nargs=2,
        action="append",
        help="Remove a repo+commit pair from the verified cache"
    )

    parser.add_argument(
        "--set-repo",
        metavar=("MODULE", "REPO"),
        nargs=2,
        action="append",
        help="Pin a module (or module@version) to the specified repository URL"
    )

    parser.add_argument(
        "--clear-repo",
        metavar="MODULE",
        nargs=1,
        action="append",
        help="Remove a previously pinned repository override (module or module@version)"
    )

    parser.add_argument(
        "--exclude-module",
        metavar="PREFIX",
        action="append",
        help="Exclude modules matching PREFIX from git:// generation (use gomod:// in recipe instead)"
    )

    parser.add_argument(
        "--scan-licenses",
        action="store_true",
        help="Scan module zips for license files and generate go-mod-licenses.inc"
    )

    parser.add_argument(
        "--common-license-dir",
        help="Path to OE-core common-licenses directory (auto-detected if not specified)"
    )

    parser.add_argument(
        "--discovery-cache",
        help="Path to discovery cache containing module .zip files (for license scanning)"
    )

    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {VERSION}"
    )

    parser.add_argument(
        "--discovered-modules",
        dest="discovered_modules",
        help="JSON file with pre-discovered module metadata (skips discovery phase)"
    )
    # Backward compatibility alias for --discovered-modules
    parser.add_argument("--native-modules", dest="discovered_modules", help=argparse.SUPPRESS)

    # Add compatibility args that we ignore (for backward compatibility)
    parser.add_argument("--use-hybrid", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("go_mod_file", nargs='?', help=argparse.SUPPRESS)

    args = parser.parse_args()
    if args.validate_only:
        args.validate = True

    # Set global verbose mode
    global VERBOSE_MODE
    VERBOSE_MODE = args.verbose

    original_stdout = sys.stdout
    original_stderr = sys.stderr
    log_handle = None
    log_path = None
    try:
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        log_path = Path(tempfile.gettempdir()) / f"oe-go-mod-fetcher-{timestamp}.log"
        LOG_PATH = log_path
        log_handle = log_path.open("w", encoding="utf-8", buffering=1)
        sys.stdout = Tee(original_stdout, log_handle)
        sys.stderr = Tee(original_stderr, log_handle)

        print(f"Go Module Git Fetcher v{VERSION}")
        print("Hybrid Architecture: Discovery from Go + Build from Git")
        print("=" * 70)
        print(f"Logs: {log_path} (pass --dry-run to load caches only)")

        exit_code = _execute(args)
    except KeyboardInterrupt:
        print("\n\nOperation cancelled by user")
        exit_code = 1
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        exit_code = 1
    finally:
        save_ls_remote_cache()
        save_metadata_cache()
        save_vanity_url_cache()
        save_verify_commit_cache()
        save_repo_overrides()
        for temp_cache in TEMP_GOMODCACHES:
            try:
                if temp_cache.exists():
                    shutil.rmtree(temp_cache)
            except Exception:
                pass
        TEMP_GOMODCACHES.clear()
        if CURRENT_GOMODCACHE and not Path(CURRENT_GOMODCACHE).exists():
            CURRENT_GOMODCACHE = None
        if log_handle:
            log_handle.flush()
            log_handle.close()
        sys.stdout = original_stdout
        sys.stderr = original_stderr
        if LOG_PATH:
            print(f"Logs: {LOG_PATH}")

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
