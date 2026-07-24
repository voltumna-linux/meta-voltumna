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
Extract complete module metadata from BitBake Go discovery build cache.

This script walks a GOMODCACHE directory (from BitBake discovery build) and
extracts all module metadata from .info files, including VCS information.

Usage:
    extract-discovered-modules.py --gomodcache /path/to/cache --output modules.json

The script creates:
    - modules.json: Complete metadata with VCS URLs, commits, subdirs, timestamps
    - modules.txt: Simple module@version list

This provides 100% accurate module discovery for BitBake recipe generation.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
from pathlib import Path


def git_ls_remote(url: str, ref: str) -> str:
    """
    Query a git repository for a ref and return the commit hash.

    For tags, also tries dereferenced form (^{}) to handle annotated tags.
    """
    try:
        # Try dereferenced form first (handles annotated tags)
        refs_to_try = [f"{ref}^{{}}", ref] if ref.startswith("refs/tags/") else [ref]

        for query_ref in refs_to_try:
            result = subprocess.run(
                ['git', 'ls-remote', url, query_ref],
                capture_output=True,
                text=True,
                timeout=30
            )
            if result.returncode == 0 and result.stdout.strip():
                # Parse: "hash<tab>ref"
                line = result.stdout.strip().split('\n')[0]
                parts = line.split('\t')
                if len(parts) >= 1 and len(parts[0]) == 40:
                    return parts[0]
    except Exception:
        pass
    return ''


def resolve_short_hash(url: str, short_hash: str) -> str:
    """
    Resolve a 12-char short hash to full 40-char hash.

    Go pseudo-versions only contain 12 characters of the commit hash.
    BitBake's git fetcher needs the full 40-char hash.

    Strategy: Try GitHub API first (fast), then git ls-remote, then shallow clone.
    """
    if len(short_hash) != 12:
        return short_hash  # Already full or invalid

    # First try: GitHub API (fast - single HTTP request)
    # Note: Rate limited to 60/hour without auth token
    if 'github.com' in url:
        try:
            import urllib.request
            repo_path = url.replace('https://github.com/', '').replace('.git', '')
            api_url = f"https://api.github.com/repos/{repo_path}/commits/{short_hash}"
            req = urllib.request.Request(api_url, headers={'User-Agent': 'oe-go-mod-fetcher'})
            with urllib.request.urlopen(req, timeout=10) as response:
                data = json.loads(response.read().decode())
                if 'sha' in data and len(data['sha']) == 40:
                    return data['sha']
        except Exception:
            pass  # Rate limited or other error - try next method

    # Second try: git ls-remote (downloads all refs, checks if any match)
    # This works if the commit is a branch head or tag
    try:
        result = subprocess.run(
            ['git', 'ls-remote', url],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0:
            for line in result.stdout.strip().split('\n'):
                if line:
                    full_hash = line.split('\t')[0]
                    if full_hash.startswith(short_hash):
                        return full_hash
    except Exception:
        pass

    # Third try: Shallow clone and rev-parse (slower but works for any commit)
    try:
        with tempfile.TemporaryDirectory(prefix='hash-resolve-') as tmpdir:
            # Clone with minimal depth
            clone_result = subprocess.run(
                ['git', 'clone', '--bare', '--filter=blob:none', url, tmpdir + '/repo'],
                capture_output=True,
                timeout=120,
                env={**os.environ, 'GIT_TERMINAL_PROMPT': '0'}
            )
            if clone_result.returncode == 0:
                # Use rev-parse to expand short hash
                parse_result = subprocess.run(
                    ['git', 'rev-parse', short_hash],
                    cwd=tmpdir + '/repo',
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                if parse_result.returncode == 0:
                    full_hash = parse_result.stdout.strip()
                    if len(full_hash) == 40:
                        return full_hash
    except Exception:
        pass

    # Could not resolve - return original short hash
    return short_hash


def derive_vcs_info(module_path, version):
    """
    Derive VCS URL and commit info from module path and version.

    This is used for modules where the Go proxy doesn't provide Origin metadata
    (older modules cached before Go 1.18).

    Returns:
        dict with vcs_url, vcs_hash (if pseudo-version), vcs_ref, subdir
        or None if cannot derive
    """
    vcs_url = None
    vcs_hash = ''
    vcs_ref = ''
    subpath = ''  # FIX #32: Track subpath for multi-module repos (tag prefix)

    # Derive URL from module path
    if module_path.startswith('github.com/'):
        # github.com/owner/repo or github.com/owner/repo/subpkg
        parts = module_path.split('/')
        if len(parts) >= 3:
            vcs_url = f"https://github.com/{parts[1]}/{parts[2]}"
            # FIX #32: Track subpath for multi-module repos (e.g., github.com/owner/repo/cmd/tool)
            if len(parts) > 3:
                subpath = '/'.join(parts[3:])

    elif module_path.startswith('gitlab.com/'):
        parts = module_path.split('/')
        if len(parts) >= 3:
            vcs_url = f"https://gitlab.com/{parts[1]}/{parts[2]}"

    elif module_path.startswith('bitbucket.org/'):
        parts = module_path.split('/')
        if len(parts) >= 3:
            vcs_url = f"https://bitbucket.org/{parts[1]}/{parts[2]}"

    elif module_path.startswith('gopkg.in/'):
        # gopkg.in/yaml.v2 -> github.com/go-yaml/yaml
        # gopkg.in/check.v1 -> github.com/go-check/check
        # gopkg.in/pkg.v3 -> github.com/go-pkg/pkg (convention)
        # gopkg.in/fsnotify.v1 -> github.com/fsnotify/fsnotify (no go- prefix)
        match = re.match(r'gopkg\.in/([^/]+)\.v\d+', module_path)
        if match:
            pkg_name = match.group(1)
            # Common mappings - some use go-* prefix, others don't
            mappings = {
                'yaml': 'https://github.com/go-yaml/yaml',
                'check': 'https://github.com/go-check/check',
                'inf': 'https://github.com/go-inf/inf',
                'tomb': 'https://github.com/go-tomb/tomb',
                'fsnotify': 'https://github.com/fsnotify/fsnotify',  # No go- prefix
            }
            vcs_url = mappings.get(pkg_name, f"https://github.com/go-{pkg_name}/{pkg_name}")

    elif module_path.startswith('google.golang.org/'):
        # google.golang.org vanity imports -> github.com/golang/*
        # google.golang.org/appengine -> github.com/golang/appengine
        # google.golang.org/protobuf -> github.com/protocolbuffers/protobuf-go (special case)
        # google.golang.org/grpc -> github.com/grpc/grpc-go (special case)
        # google.golang.org/genproto -> github.com/googleapis/go-genproto (special case)
        #
        # FIX #32: Handle submodules in multi-module repos
        # google.golang.org/grpc/cmd/protoc-gen-go-grpc has tags like:
        #   cmd/protoc-gen-go-grpc/v1.1.0 (NOT v1.1.0)
        # We need to track the subpath for tag prefix construction
        parts = module_path.split('/')
        if len(parts) >= 2:
            pkg_name = parts[1]  # First component after google.golang.org/
            mappings = {
                'protobuf': 'https://github.com/protocolbuffers/protobuf-go',
                'grpc': 'https://github.com/grpc/grpc-go',
                'genproto': 'https://github.com/googleapis/go-genproto',
                'api': 'https://github.com/googleapis/google-api-go-client',
            }
            vcs_url = mappings.get(pkg_name, f"https://github.com/golang/{pkg_name}")
            # Track subpath for submodule tag construction (e.g., cmd/protoc-gen-go-grpc)
            if len(parts) > 2:
                subpath = '/'.join(parts[2:])  # Everything after google.golang.org/grpc/

    if not vcs_url:
        return None

    # Parse version for commit hash (pseudo-versions)
    # Go pseudo-version formats:
    #   v0.0.0-20200815063812-42c35b437635           (no base version)
    #   v1.2.3-0.20200815063812-42c35b437635         (pre-release with "0." prefix)
    #   v1.2.4-0.20200815063812-42c35b437635         (post v1.2.3, pre v1.2.4)
    # The key pattern: optional "0." then YYYYMMDDHHMMSS (14 digits) then 12-char commit hash
    # Also handle +incompatible suffix
    clean_version = version.replace('+incompatible', '')

    # Try both pseudo-version formats:
    # Format 1: -0.YYYYMMDDHHMMSS-HASH (with "0." prefix)
    # Format 2: -YYYYMMDDHHMMSS-HASH (without prefix, typically v0.0.0-...)
    pseudo_match = re.search(r'-(?:0\.)?(\d{14})-([0-9a-f]{12})$', clean_version)
    if pseudo_match:
        vcs_hash = pseudo_match.group(2)  # 12-char short hash
        # Note: Short hashes are expanded to full 40-char by oe-go-mod-fetcher.py
        # in load_native_modules() using resolve_pseudo_version_commit()
    else:
        # Tagged version - resolve tag to commit hash
        # FIX #32: For multi-module repos, the tag includes the subpath prefix
        # e.g., google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.1.0
        #       has tag: cmd/protoc-gen-go-grpc/v1.1.0 (not v1.1.0)
        if subpath:
            tag_name = f"{subpath}/{clean_version}"
        else:
            tag_name = clean_version
        vcs_ref = f"refs/tags/{tag_name}"
        # Query the repository to get the actual commit hash for this tag
        vcs_hash = git_ls_remote(vcs_url, vcs_ref)
        if not vcs_hash and subpath:
            # FIX #32: Fallback - try without subpath prefix
            # Some repos don't use prefixed tags for submodules
            fallback_ref = f"refs/tags/{clean_version}"
            vcs_hash = git_ls_remote(vcs_url, fallback_ref)
            if vcs_hash:
                vcs_ref = fallback_ref  # Use the working ref

    return {
        'vcs_url': vcs_url,
        'vcs_hash': vcs_hash,
        'vcs_ref': vcs_ref,
        'subdir': subpath,  # FIX #32: Return subdir for submodules
    }


def extract_modules(gomodcache_path):
    """
    Walk GOMODCACHE and extract all module metadata from .info files.

    Returns list of dicts with complete metadata:
    - module_path: Unescaped module path
    - version: Module version
    - vcs_url: Git repository URL
    - vcs_hash: Full commit hash (40 chars)
    - vcs_ref: Tag/branch reference
    - subdir: Subdirectory in mono-repos
    - timestamp: Commit timestamp
    """
    cache_dir = Path(gomodcache_path) / "cache" / "download"

    if not cache_dir.exists():
        raise FileNotFoundError(f"Cache directory not found: {cache_dir}")

    modules = []
    skipped = 0
    derived = 0
    total_info_files = 0

    print(f"Scanning GOMODCACHE: {cache_dir}")

    for info_file in cache_dir.rglob("*.info"):
        total_info_files += 1

        # Extract module path from directory structure
        rel_path = info_file.parent.relative_to(cache_dir)
        parts = list(rel_path.parts)

        if parts[-1] != '@v':
            continue

        # Module path (unescape Go's !-encoding)
        # Example: github.com/!microsoft/go-winio -> github.com/Microsoft/go-winio
        module_path = '/'.join(parts[:-1])
        # Unescape !x -> X (Go's case-insensitive encoding)
        module_path = re.sub(r'!([a-z])', lambda m: m.group(1).upper(), module_path)

        # Version
        version = info_file.stem

        # Read .info file for VCS metadata
        try:
            with open(info_file) as f:
                info = json.load(f)

            origin = info.get('Origin', {})

            # Check if we have complete VCS info from Origin
            if origin.get('URL') and origin.get('Hash'):
                module = {
                    'module_path': module_path,
                    'version': version,
                    'vcs_url': origin.get('URL', ''),
                    'vcs_hash': origin.get('Hash', ''),
                    'vcs_ref': origin.get('Ref', ''),
                    'subdir': origin.get('Subdir', ''),
                    'timestamp': info.get('Time', ''),
                }
                modules.append(module)
            else:
                # FIX #29: Module lacks Origin metadata (common for +incompatible modules)
                # Use derive_vcs_info() to infer VCS URL and ref from module path/version
                derived += 1
                # Progress output for derived modules (these require network calls)
                if derived % 10 == 1:
                    print(f"  Deriving VCS info... ({derived} modules)", end='\r', flush=True)
                derived_info = derive_vcs_info(module_path, version)
                if derived_info:
                    module = {
                        'module_path': module_path,
                        'version': version,
                        'vcs_url': derived_info.get('vcs_url', ''),
                        'vcs_hash': derived_info.get('vcs_hash', ''),
                        'vcs_ref': derived_info.get('vcs_ref', ''),
                        'subdir': derived_info.get('subdir', ''),  # FIX #32: Use derived subdir
                        'timestamp': info.get('Time', ''),
                    }
                    modules.append(module)
                else:
                    # Cannot derive VCS info - skip this module
                    skipped += 1
                    derived -= 1  # Don't count as derived if we couldn't derive
                    # Only log for debugging
                    # print(f"  ⚠️  Cannot derive VCS info for {module_path}@{version}")

        except json.JSONDecodeError as e:
            print(f"  ⚠️  Failed to parse {info_file}: {e}")
            skipped += 1
            continue
        except Exception as e:
            print(f"  ⚠️  Error processing {info_file}: {e}")
            skipped += 1
            continue

    print(f"\nProcessed {total_info_files} .info files")
    print(f"Extracted {len(modules)} modules total:")
    print(f"  - {len(modules) - derived} with Origin metadata from proxy")
    print(f"  - {derived} with derived VCS info (Fix #29)")
    print(f"Skipped {skipped} modules (cannot derive VCS info)")

    return modules


def main():
    parser = argparse.ArgumentParser(
        description='Extract module metadata from Go module cache',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Extract from native Go build cache
    %(prog)s --gomodcache /tmp/k3s-discovery-cache --output /tmp/k3s-modules.json

    # Extract from BitBake discovery build
    %(prog)s --gomodcache /path/to/build/tmp/work/.../discovery-cache --output /tmp/k3s-modules.json

    # Extract from system GOMODCACHE
    %(prog)s --gomodcache ~/go/pkg/mod --output /tmp/modules.json

Output:
    - <output>.json: Complete module metadata (VCS URLs, commits, subdirs)
    - <output>.txt: Simple module@version list (sorted)
"""
    )
    parser.add_argument(
        '--gomodcache',
        required=True,
        help='Path to GOMODCACHE directory'
    )
    parser.add_argument(
        '--output',
        required=True,
        help='Output JSON file path (e.g., /tmp/k3s-modules.json)'
    )

    args = parser.parse_args()

    # Validate GOMODCACHE path
    gomodcache = Path(args.gomodcache)
    if not gomodcache.exists():
        print(f"Error: GOMODCACHE directory does not exist: {gomodcache}", file=sys.stderr)
        sys.exit(1)

    # Extract modules
    try:
        modules = extract_modules(gomodcache)
    except Exception as e:
        print(f"Error during extraction: {e}", file=sys.stderr)
        sys.exit(1)

    if not modules:
        print("Warning: No modules with VCS metadata found!", file=sys.stderr)
        print("This may indicate:", file=sys.stderr)
        print("  - GOMODCACHE is from BitBake (synthetic .info files)", file=sys.stderr)
        print("  - GOMODCACHE is empty or incomplete", file=sys.stderr)
        print("  - Need to run 'go mod download' first", file=sys.stderr)
        sys.exit(1)

    # Save as JSON
    output_path = Path(args.output)
    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(modules, indent=2, sort_keys=True))
        print(f"\n✓ Saved {len(modules)} modules to {output_path}")
    except Exception as e:
        print(f"Error writing JSON output: {e}", file=sys.stderr)
        sys.exit(1)

    # Also save simple list
    list_path = output_path.with_suffix('.txt')
    try:
        simple_list = [f"{m['module_path']}@{m['version']}" for m in modules]
        list_path.write_text('\n'.join(sorted(simple_list)) + '\n')
        print(f"✓ Saved module list to {list_path}")
    except Exception as e:
        print(f"Error writing module list: {e}", file=sys.stderr)
        sys.exit(1)

    # Print summary statistics
    print("\n" + "="*60)
    print("EXTRACTION SUMMARY")
    print("="*60)

    # Count unique repositories
    unique_repos = len(set(m['vcs_url'] for m in modules))
    print(f"Total modules:      {len(modules)}")
    print(f"Unique repositories: {unique_repos}")

    # Count modules with subdirs (multi-module repos)
    with_subdirs = sum(1 for m in modules if m['subdir'])
    print(f"Multi-module repos:  {with_subdirs} modules have subdirs")

    # Show top repositories by module count
    repo_counts = {}
    for m in modules:
        repo_counts[m['vcs_url']] = repo_counts.get(m['vcs_url'], 0) + 1

    top_repos = sorted(repo_counts.items(), key=lambda x: x[1], reverse=True)[:5]
    print("\nTop 5 repositories by module count:")
    for repo_url, count in top_repos:
        print(f"  {count:3d} modules: {repo_url}")

    print("\n" + "="*60)
    print("Use this JSON file with:")
    print(f"  oe-go-mod-fetcher.py --native-modules {output_path}")
    print("="*60)


if __name__ == '__main__':
    main()
