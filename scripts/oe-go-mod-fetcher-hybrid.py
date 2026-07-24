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
oe-go-mod-fetcher-hybrid.py - Convert go-mod-vcs format to hybrid gomod:// + git:// format.

This script reads existing go-mod-git.inc and go-mod-cache.inc files and converts
them to a hybrid format that uses:
- gomod:// for modules fetched from proxy.golang.org (fast, but no VCS control)
- git:// for modules where you want SRCREV control (auditable, but slower)

Usage:
    # List all modules and their sizes
    oe-go-mod-fetcher-hybrid.py --recipedir ./recipes-containers/k3s --list

    # Show size-based recommendations
    oe-go-mod-fetcher-hybrid.py --recipedir ./recipes-containers/k3s --recommend

    # Convert specific modules to gomod:// (rest stay as git://)
    oe-go-mod-fetcher-hybrid.py --recipedir ./recipes-containers/k3s \\
        --gomod "github.com/spf13,golang.org/x,google.golang.org"

    # Convert specific modules to git:// (rest become gomod://)
    oe-go-mod-fetcher-hybrid.py --recipedir ./recipes-containers/k3s \\
        --git "github.com/containerd,github.com/rancher"

    # Use a config file
    oe-go-mod-fetcher-hybrid.py --recipedir ./recipes-containers/k3s \\
        --config hybrid-config.json
"""

import argparse
import json
import re
import sys
import subprocess
import os
import hashlib
import urllib.request
import urllib.error
import concurrent.futures
from pathlib import Path
from collections import defaultdict
from typing import Optional


# Default configuration - used if data/hybrid-config.json is not found
DEFAULT_CONFIG = {
    "vcs_priority_prefixes": [
        "github.com/containerd",
        "github.com/rancher",
        "github.com/k3s-io",
        "k8s.io",
        "sigs.k8s.io",
    ],
    "size_threshold_bytes": 1048576,  # 1MB
    "default_git_prefixes": [
        "github.com/containerd",
        "k8s.io",
        "sigs.k8s.io",
    ],
}


def load_hybrid_config() -> dict:
    """
    Load hybrid mode configuration from data/hybrid-config.json.

    Falls back to DEFAULT_CONFIG if the file doesn't exist.
    The config file is looked for relative to this script's location.
    """
    script_dir = Path(__file__).parent
    config_path = script_dir / "data" / "hybrid-config.json"

    if config_path.exists():
        try:
            with open(config_path) as f:
                config = json.load(f)
            # Merge with defaults for any missing keys
            for key, value in DEFAULT_CONFIG.items():
                if key not in config:
                    config[key] = value
            return config
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Could not load {config_path}: {e}", file=sys.stderr)
            print("Using default configuration", file=sys.stderr)

    return DEFAULT_CONFIG.copy()


def fetch_gomod_checksum(module: str, version: str) -> Optional[str]:
    """
    Fetch SHA256 checksum for a module from proxy.golang.org.

    The checksum is calculated by downloading the .zip file and hashing it.
    """
    # Escape capital letters in module path (Go proxy convention)
    escaped_module = re.sub(r'([A-Z])', lambda m: '!' + m.group(1).lower(), module)
    escaped_version = re.sub(r'([A-Z])', lambda m: '!' + m.group(1).lower(), version)

    url = f"https://proxy.golang.org/{escaped_module}/@v/{escaped_version}.zip"

    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'oe-go-mod-fetcher-hybrid/1.0'})
        with urllib.request.urlopen(req, timeout=30) as response:
            data = response.read()
            return hashlib.sha256(data).hexdigest()
    except urllib.error.HTTPError as e:
        print(f"    WARNING: Failed to fetch {module}@{version}: HTTP {e.code}", file=sys.stderr)
        return None
    except urllib.error.URLError as e:
        print(f"    WARNING: Failed to fetch {module}@{version}: {e.reason}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"    WARNING: Failed to fetch {module}@{version}: {e}", file=sys.stderr)
        return None


def fetch_checksums_parallel(modules: list[dict], max_workers: int = 8) -> dict[str, str]:
    """
    Fetch checksums for multiple modules in parallel.

    Returns dict mapping "module@version" -> "sha256sum"
    """
    checksums = {}

    def fetch_one(mod):
        key = f"{mod['module']}@{mod['version']}"
        checksum = fetch_gomod_checksum(mod['module'], mod['version'])
        return key, checksum

    print(f"Fetching checksums for {len(modules)} modules from proxy.golang.org...")

    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(fetch_one, mod): mod for mod in modules}
        completed = 0
        for future in concurrent.futures.as_completed(futures):
            key, checksum = future.result()
            completed += 1
            if checksum:
                checksums[key] = checksum
            # Progress indicator
            if completed % 20 == 0 or completed == len(modules):
                print(f"  Progress: {completed}/{len(modules)} modules")

    return checksums


def parse_go_mod_cache_inc(cache_inc_path: Path) -> list[dict]:
    """Parse GO_MODULE_CACHE_DATA from go-mod-cache.inc."""
    content = cache_inc_path.read_text()

    # Find the JSON array in GO_MODULE_CACHE_DATA
    match = re.search(r"GO_MODULE_CACHE_DATA\s*=\s*'(\[.*\])'", content, re.DOTALL)
    if not match:
        raise ValueError(f"Could not find GO_MODULE_CACHE_DATA in {cache_inc_path}")

    json_str = match.group(1).replace('\\\n', '')
    return json.loads(json_str)


def parse_go_mod_git_inc(git_inc_path: Path) -> dict[str, dict]:
    """Parse SRC_URI entries from go-mod-git.inc to extract commit and repo info."""
    content = git_inc_path.read_text()

    # Map vcs_hash -> {repo, commit, full_entry}
    vcs_to_info = {}

    # Pattern: git://host/path;...;rev=COMMIT;...;destsuffix=vcs_cache/VCS_HASH
    for line in content.split('\n'):
        if not line.startswith('SRC_URI +='):
            continue

        # Extract the git:// URL part
        match = re.search(r'git://([^;]+);([^"]*);destsuffix=vcs_cache/([a-f0-9]+)', line)
        if match:
            repo_path = match.group(1)
            params = match.group(2)
            vcs_hash = match.group(3)

            # Extract rev from params
            rev_match = re.search(r'rev=([a-f0-9]+)', params)
            commit = rev_match.group(1) if rev_match else ''

            vcs_to_info[vcs_hash] = {
                'repo': f"https://{repo_path}",
                'commit': commit,
                'full_line': line.strip()
            }

    return vcs_to_info


def get_repo_sizes(vcs_info: dict, workdir: Optional[Path] = None) -> dict[str, int]:
    """Get sizes of VCS cache directories if they exist."""
    sizes = {}

    if workdir is None:
        return sizes

    # Try common locations for vcs_cache
    for subpath in ['sources/vcs_cache', 'vcs_cache']:
        vcs_cache_dir = workdir / subpath
        if vcs_cache_dir.exists():
            break
    else:
        return sizes

    for vcs_hash in vcs_info.keys():
        cache_path = vcs_cache_dir / vcs_hash
        if cache_path.exists():
            try:
                result = subprocess.run(
                    ['du', '-sb', str(cache_path)],
                    capture_output=True, text=True, timeout=10
                )
                if result.returncode == 0:
                    size = int(result.stdout.split()[0])
                    sizes[vcs_hash] = size
            except (subprocess.TimeoutExpired, ValueError):
                pass

    return sizes


def get_discovery_sizes(modules: list[dict], discovery_cache: Optional[Path] = None) -> dict[str, int]:
    """Get sizes of modules from discovery cache .zip files."""
    sizes = {}

    if discovery_cache is None or not discovery_cache.exists():
        return sizes

    for mod in modules:
        module_path = mod.get('module', '')
        version = mod.get('version', '')
        vcs_hash = mod.get('vcs_hash', '')

        if not module_path or not version or not vcs_hash:
            continue

        # Build path to .zip file: discovery_cache/<module>/@v/<version>.zip
        zip_path = discovery_cache / module_path / '@v' / f'{version}.zip'

        if zip_path.exists():
            try:
                size = zip_path.stat().st_size
                # Accumulate size by vcs_hash (same repo may have multiple modules)
                sizes[vcs_hash] = sizes.get(vcs_hash, 0) + size
            except OSError:
                pass

    return sizes


def format_size(size_bytes: int) -> str:
    """Format bytes as human readable."""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size_bytes < 1024:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024
    return f"{size_bytes:.1f} TB"


def list_modules(modules: list[dict], vcs_info: dict, sizes: dict) -> None:
    """List all modules with their info."""
    # Group by module path prefix
    by_prefix = defaultdict(list)
    for mod in modules:
        parts = mod['module'].split('/')
        if len(parts) >= 2:
            prefix = '/'.join(parts[:2])
        else:
            prefix = mod['module']
        by_prefix[prefix].append(mod)

    print(f"\n{'Module':<60} {'Version':<25} {'Size':>12}")
    print("=" * 100)

    total_size = 0
    for prefix in sorted(by_prefix.keys()):
        prefix_size = 0
        for mod in sorted(by_prefix[prefix], key=lambda m: m['module']):
            vcs_hash = mod.get('vcs_hash', '')
            size = sizes.get(vcs_hash, 0)
            prefix_size += size
            total_size += size

            size_str = format_size(size) if size > 0 else '-'
            print(f"  {mod['module']:<58} {mod['version']:<25} {size_str:>12}")

        if len(by_prefix[prefix]) > 1:
            print(f"  {'[subtotal]':<58} {'':<25} {format_size(prefix_size):>12}")
        print()

    print("=" * 100)
    print(f"Total: {len(modules)} modules, {format_size(total_size)}")


def recommend_conversion(modules: list[dict], vcs_info: dict, sizes: dict, recipedir: Path = None) -> None:
    """Recommend modules to convert based on size.

    Configuration is loaded from data/hybrid-config.json if it exists,
    otherwise defaults are used. This allows easy customization of:
    - vcs_priority_prefixes: modules to suggest keeping as git://
    - size_threshold_bytes: threshold for suggesting gomod:// conversion
    - default_git_prefixes: fallback prefixes if no matches found
    """
    # Load configuration from external file (or use defaults)
    config = load_hybrid_config()
    vcs_priority_patterns = config.get('vcs_priority_prefixes', DEFAULT_CONFIG['vcs_priority_prefixes'])
    size_threshold = config.get('size_threshold_bytes', DEFAULT_CONFIG['size_threshold_bytes'])
    default_git_prefixes = config.get('default_git_prefixes', DEFAULT_CONFIG['default_git_prefixes'])

    # Calculate sizes per prefix
    prefix_sizes = defaultdict(lambda: {'size': 0, 'count': 0, 'modules': []})

    for mod in modules:
        parts = mod['module'].split('/')
        if len(parts) >= 2:
            prefix = '/'.join(parts[:2])
        else:
            prefix = mod['module']

        vcs_hash = mod.get('vcs_hash', '')
        size = sizes.get(vcs_hash, 0)

        prefix_sizes[prefix]['size'] += size
        prefix_sizes[prefix]['count'] += 1
        prefix_sizes[prefix]['modules'].append(mod['module'])

    # Sort by size descending
    sorted_prefixes = sorted(prefix_sizes.items(), key=lambda x: x[1]['size'], reverse=True)

    total_size = sum(p['size'] for p in prefix_sizes.values())

    print("\n" + "=" * 80)
    print("GO MODULE HYBRID CONVERSION RECOMMENDATIONS")
    print("=" * 80)

    print(f"\n{'Prefix':<45} {'Count':>8} {'Size':>12} {'% Total':>10}")
    print("-" * 80)

    gomod_candidates = []
    git_candidates = []

    for prefix, info in sorted_prefixes[:25]:  # Top 25
        pct = (info['size'] / total_size * 100) if total_size > 0 else 0

        print(f"{prefix:<45} {info['count']:>8} {format_size(info['size']):>12} {pct:>9.1f}%")

        # Check if this is a VCS priority prefix
        is_vcs_priority = any(prefix.startswith(p) or prefix == p for p in vcs_priority_patterns)

        if is_vcs_priority:
            git_candidates.append(prefix)
        elif info['size'] > size_threshold:
            gomod_candidates.append(prefix)

    print("-" * 80)
    print(f"{'Total':<45} {len(modules):>8} {format_size(total_size):>12}")

    if gomod_candidates:
        print("\n" + "=" * 80)
        print("LARGEST MODULE PREFIXES (top candidates for gomod:// proxy fetch):")
        print("=" * 80)
        print("\n  " + ",".join(gomod_candidates[:10]))

        # Calculate potential savings
        gomod_size = sum(prefix_sizes[p]['size'] for p in gomod_candidates)
        if total_size > 0:
            print(f"\n  These account for {format_size(gomod_size)} ({gomod_size/total_size*100:.0f}% of total)")

    print("\n" + "=" * 80)
    print("SUGGESTED --git PREFIXES (keep as git:// for VCS control):")
    print("=" * 80)

    if git_candidates:
        print("\n  " + ",".join(git_candidates))
    else:
        print("\n  (none identified)")

    print("\n  NOTE: With --git, ALL other modules automatically become gomod://")
    print("        (not just the large ones listed above)")

    # Output conversion command
    print("\n" + "=" * 80)
    print("TO CONVERT TO HYBRID FORMAT:")
    print("=" * 80)
    print()

    # Get script path (relative to this script's location)
    script_path = Path(__file__).resolve()

    # Use default_git_prefixes from config as fallback
    fallback_git = ','.join(default_git_prefixes)

    if recipedir:
        print(f"  python3 {script_path} \\")
        print(f"    --recipedir {recipedir} \\")
        if git_candidates:
            print(f"    --git \"{','.join(git_candidates)}\"")
        else:
            print(f"    --git \"{fallback_git}\"")
    else:
        print(f"  python3 {script_path} \\")
        print(f"    --recipedir <your-recipe-directory> \\")
        if git_candidates:
            print(f"    --git \"{','.join(git_candidates)}\"")
        else:
            print(f"    --git \"{fallback_git}\"")


def fetch_gomod_checksum(module: str, version: str) -> Optional[str]:
    """Fetch SHA256 checksum for a module from proxy.golang.org."""
    import urllib.request
    import hashlib

    # Escape module path (uppercase letters)
    escaped = re.sub(r'([A-Z])', lambda m: '!' + m.group(1).lower(), module)

    url = f"https://proxy.golang.org/{escaped}/@v/{version}.zip"

    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            content = response.read()
            return hashlib.sha256(content).hexdigest()
    except Exception as e:
        print(f"  Warning: Could not fetch checksum for {module}@{version}: {e}", file=sys.stderr)
        return None


def generate_hybrid_files(
    modules: list[dict],
    vcs_info: dict,
    git_prefixes: list[str],
    gomod_prefixes: list[str],
    output_dir: Path,
    fetch_checksums: bool = False
) -> None:
    """Generate hybrid include files."""

    # Ensure output directory exists
    output_dir.mkdir(parents=True, exist_ok=True)

    git_modules = []
    gomod_modules = []

    # Classify modules
    for mod in modules:
        mod_path = mod['module']

        # Check if explicitly marked as git://
        is_git = any(mod_path.startswith(prefix) for prefix in git_prefixes)

        # Check if explicitly marked as gomod://
        is_gomod = any(mod_path.startswith(prefix) for prefix in gomod_prefixes)

        if is_git and is_gomod:
            print(f"Warning: {mod_path} matches both git and gomod prefixes, using git://",
                  file=sys.stderr)
            is_gomod = False

        # Default: if git_prefixes specified, everything else is gomod
        # If gomod_prefixes specified, everything else is git
        if git_prefixes and not is_git and not is_gomod:
            is_gomod = True
        elif gomod_prefixes and not is_git and not is_gomod:
            is_git = True
        elif not git_prefixes and not gomod_prefixes:
            # No prefixes specified - default to gomod for all
            is_gomod = True

        if is_gomod:
            gomod_modules.append(mod)
        else:
            git_modules.append(mod)

    print(f"\nClassification:")
    print(f"  gomod:// (proxy): {len(gomod_modules)} modules")
    print(f"  git:// (VCS):     {len(git_modules)} modules")

    # Fetch checksums in parallel (always, unless --no-checksums)
    checksum_map = {}
    if fetch_checksums and gomod_modules:
        checksum_map = fetch_checksums_parallel(gomod_modules)
        if len(checksum_map) < len(gomod_modules):
            missing = len(gomod_modules) - len(checksum_map)
            print(f"  WARNING: Failed to fetch {missing} checksums", file=sys.stderr)

    # Generate gomod include file
    gomod_lines = [
        "# Generated by oe-go-mod-fetcher-hybrid.py",
        "# Go modules fetched from proxy.golang.org (fast path)",
        "#",
        "# These modules are fetched as pre-built zip files from the Go proxy.",
        "# They do not provide VCS commit-level provenance but are much faster.",
        "",
        "inherit go-mod",
        ""
    ]

    for mod in sorted(gomod_modules, key=lambda m: m['module']):
        key = f"{mod['module']}@{mod['version']}"
        if key in checksum_map:
            # Include checksum inline to avoid BitBake variable flag name issues
            # (e.g., ~ character in git.sr.ht/~sbinet/gg causes parse errors)
            gomod_lines.append(f'SRC_URI += "gomod://{mod["module"]};version={mod["version"]};sha256sum={checksum_map[key]}"')
        else:
            gomod_lines.append(f'SRC_URI += "gomod://{mod["module"]};version={mod["version"]}"')

    gomod_file = output_dir / 'go-mod-hybrid-gomod.inc'
    gomod_file.write_text('\n'.join(gomod_lines) + '\n')
    print(f"\nWrote {gomod_file}")

    if not fetch_checksums and gomod_modules:
        print(f"  WARNING: Checksums not fetched (use default or --fetch-checksums)")
        print(f"           BitBake will fail on first fetch and show required checksums")

    # Generate git include file
    git_lines = [
        "# Generated by oe-go-mod-fetcher-hybrid.py",
        "# Go modules fetched from git repositories (VCS path)",
        "#",
        "# These modules are fetched directly from their git repositories.",
        "# They provide full VCS provenance and allow easy SRCREV bumping.",
        ""
    ]

    # Track added vcs_hashes to avoid duplicates when multiple modules
    # share the same git repo/commit (e.g., errdefs and errdefs/pkg)
    added_vcs_hashes = set()
    for mod in sorted(git_modules, key=lambda m: m['module']):
        vcs_hash = mod.get('vcs_hash', '')
        if vcs_hash in vcs_info and vcs_hash not in added_vcs_hashes:
            git_lines.append(vcs_info[vcs_hash]['full_line'])
            added_vcs_hashes.add(vcs_hash)

    git_file = output_dir / 'go-mod-hybrid-git.inc'
    git_file.write_text('\n'.join(git_lines) + '\n')
    print(f"Wrote {git_file}")

    # Generate cache metadata file for git modules
    cache_lines = [
        "# Generated by oe-go-mod-fetcher-hybrid.py",
        "# Metadata for git-fetched modules (VCS path)",
        "# Used by go-mod-vcs.bbclass to build module cache from git checkouts",
        "",
        "inherit go-mod-vcs",
        "",
    ]

    # Format GO_MODULE_CACHE_DATA with one entry per line for readability
    # (matches go-mod-cache.inc format: '[\
    # {entry1},\
    # {entry2}]')
    cache_lines.append("# Module metadata for cache building (one module per line)")
    if git_modules:
        cache_lines.append("GO_MODULE_CACHE_DATA = '[\\")
        for i, mod in enumerate(sorted(git_modules, key=lambda m: m['module'])):
            entry = json.dumps(mod, separators=(',', ':'))  # Compact single-line JSON per entry
            if i < len(git_modules) - 1:
                cache_lines.append(f"{entry},\\")
            else:
                cache_lines.append(f"{entry}]'")
    else:
        cache_lines.append("GO_MODULE_CACHE_DATA = '[]'")

    cache_file = output_dir / 'go-mod-hybrid-cache.inc'
    cache_file.write_text('\n'.join(cache_lines) + '\n')
    print(f"Wrote {cache_file}")

    # Print usage instructions
    print("\n" + "=" * 70)
    print("NEXT STEPS:")
    print("=" * 70)
    print("""
1. Update your recipe to enable mode switching:

   # GO_MOD_FETCH_MODE: "vcs" (all git://) or "hybrid" (gomod:// + git://)
   GO_MOD_FETCH_MODE ?= "vcs"

   # VCS mode: all modules via git://
   include ${@ "go-mod-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}
   include ${@ "go-mod-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}

   # Hybrid mode: gomod:// for most, git:// for selected
   include ${@ "go-mod-hybrid-gomod.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
   include ${@ "go-mod-hybrid-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
   include ${@ "go-mod-hybrid-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}

2. Run bitbake once in hybrid mode to fetch gomod:// checksums:

   GO_MOD_FETCH_MODE = "hybrid"   # in local.conf
   bitbake <recipe>

3. Copy the checksums from the error log into go-mod-hybrid-gomod.inc

4. Build again - or switch back to VCS mode anytime:

   GO_MOD_FETCH_MODE = "vcs"      # full VCS provenance
   GO_MOD_FETCH_MODE = "hybrid"   # faster proxy fetch
""")


def main():
    parser = argparse.ArgumentParser(
        description='Convert go-mod-vcs format to hybrid gomod:// + git:// format',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )

    parser.add_argument('--recipedir', type=Path, required=True,
                        help='Recipe directory containing go-mod-git.inc and go-mod-cache.inc')

    parser.add_argument('--workdir', type=Path, default=None,
                        help='BitBake workdir containing vcs_cache (for size calculations)')

    parser.add_argument('--discovery-cache', type=Path, default=None,
                        help='Discovery cache directory containing module .zip files (for size calculations)')

    # Actions
    parser.add_argument('--list', action='store_true',
                        help='List all modules with sizes')

    parser.add_argument('--recommend', action='store_true',
                        help='Show size-based recommendations for conversion')

    # Conversion options
    parser.add_argument('--git', type=str, default='',
                        help='Comma-separated module prefixes to keep as git:// (rest become gomod://)')

    parser.add_argument('--gomod', type=str, default='',
                        help='Comma-separated module prefixes to convert to gomod:// (rest stay git://)')

    parser.add_argument('--config', type=Path, default=None,
                        help='JSON config file with git/gomod prefix lists')

    parser.add_argument('--no-checksums', action='store_true',
                        help='Skip fetching SHA256 checksums (not recommended)')

    parser.add_argument('--output-dir', type=Path, default=None,
                        help='Output directory for hybrid files (default: recipedir)')

    args = parser.parse_args()

    # Validate inputs
    cache_inc = args.recipedir / 'go-mod-cache.inc'
    git_inc = args.recipedir / 'go-mod-git.inc'

    if not cache_inc.exists():
        print(f"Error: {cache_inc} not found", file=sys.stderr)
        sys.exit(1)

    if not git_inc.exists():
        print(f"Error: {git_inc} not found", file=sys.stderr)
        sys.exit(1)

    # Parse existing files
    print(f"Loading {cache_inc}...")
    modules = parse_go_mod_cache_inc(cache_inc)
    print(f"  Found {len(modules)} modules")

    print(f"Loading {git_inc}...")
    vcs_info = parse_go_mod_git_inc(git_inc)
    print(f"  Found {len(vcs_info)} VCS entries")

    # Get sizes from discovery cache and/or workdir
    sizes = {}
    if args.discovery_cache:
        print(f"Calculating sizes from discovery cache {args.discovery_cache}...")
        sizes = get_discovery_sizes(modules, args.discovery_cache)
        print(f"  Got sizes for {len(sizes)} modules from discovery cache")

    if args.workdir:
        print(f"Calculating sizes from {args.workdir}...")
        vcs_sizes = get_repo_sizes(vcs_info, args.workdir)
        print(f"  Got sizes for {len(vcs_sizes)} repos from vcs_cache")
        # Merge vcs_sizes into sizes (vcs_cache sizes override discovery if both exist)
        for k, v in vcs_sizes.items():
            sizes[k] = v

    # Handle actions
    if args.list:
        list_modules(modules, vcs_info, sizes)
        return

    if args.recommend:
        recommend_conversion(modules, vcs_info, sizes, args.recipedir)
        return

    # Handle conversion
    git_prefixes = [p.strip() for p in args.git.split(',') if p.strip()]
    gomod_prefixes = [p.strip() for p in args.gomod.split(',') if p.strip()]

    if args.config:
        if args.config.exists():
            config = json.loads(args.config.read_text())
            git_prefixes.extend(config.get('git', []))
            gomod_prefixes.extend(config.get('gomod', []))
        else:
            print(f"Error: Config file {args.config} not found", file=sys.stderr)
            sys.exit(1)

    if not git_prefixes and not gomod_prefixes:
        print("Error: Specify --git, --gomod, --list, or --recommend", file=sys.stderr)
        parser.print_help()
        sys.exit(1)

    output_dir = args.output_dir or args.recipedir

    generate_hybrid_files(
        modules=modules,
        vcs_info=vcs_info,
        git_prefixes=git_prefixes,
        gomod_prefixes=gomod_prefixes,
        output_dir=output_dir,
        fetch_checksums=not args.no_checksums  # Default: fetch checksums
    )


if __name__ == '__main__':
    main()
