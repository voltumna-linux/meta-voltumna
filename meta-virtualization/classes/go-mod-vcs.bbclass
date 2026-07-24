#
# Copyright OpenEmbedded Contributors
#
# SPDX-License-Identifier: MIT
#

# go-mod-vcs.bbclass
#
# Provides tasks for building Go module cache from VCS (git) sources.
# This enables fully offline Go builds using modules fetched via BitBake's
# git fetcher instead of the Go proxy.
#
# USAGE:
#   1. Add to recipe: inherit go-mod-vcs
#   2. Define GO_MODULE_CACHE_DATA as JSON array of module metadata
#   3. Include go-mod-git.inc for SRC_URI git entries
#   4. Include go-mod-cache.inc for GO_MODULE_CACHE_DATA
#
# DEPENDENCIES:
#   - Works with oe-core's go.bbclass and go-mod.bbclass
#   - h1: checksums calculated in pure Python (with go-dirhash-native fallback)
#   - Optional: go-dirhash-native for fallback checksum calculation
#
# TASKS PROVIDED:
#   - do_create_module_cache: Builds module cache from git repos
#   - do_sync_go_files: Synchronizes go.sum with cache checksums
#
# GENERATED FILES:
#   The oe-go-mod-fetcher.py script generates two .inc files per recipe:
#   - go-mod-git.inc: SRC_URI and SRCREV entries for git fetching
#   - go-mod-cache.inc: GO_MODULE_CACHE_DATA JSON + inherit go-mod-vcs
#
# This class extracts the reusable Python task code, so generated .inc files
# only contain recipe-specific data (SRC_URI entries and module metadata).
#
# ARCHITECTURE NOTES:
#   - assemble_zip() must create zips INSIDE TemporaryDirectory context
#   - synthesize_go_mod() preserves go version directive from original go.mod
#
# CONFIGURATION:
#   GO_MOD_SKIP_ZIP_EXTRACTION - Set to "1" to skip extracting zips to pkg/mod
#                                Go can extract on-demand from cache (experimental)
#

# Override go.bbclass defaults for VCS-based module caching
# These ensure offline builds use our pre-built module cache
export GOMODCACHE = "${S}/pkg/mod"
export GOPROXY = "off"
export GOSUMDB = "off"
export GOTOOLCHAIN = "local"

python do_create_module_cache() {
    """
    Build Go module cache from downloaded git repositories.
    This creates the same cache structure as oe-core's gomod.bbclass.

    NOTE: h1: checksums are calculated in pure Python during zip creation.
    Falls back to go-dirhash-native if Python hash fails.
    """
    import hashlib
    import json
    import os
    import shutil
    import subprocess
    import zipfile
    import stat
    import base64
    from pathlib import Path
    from datetime import datetime

    # Check for optional go-dirhash-native fallback tool
    go_dirhash_helper = Path(d.getVar('STAGING_BINDIR_NATIVE') or '') / "dirhash"
    if not go_dirhash_helper.exists():
        go_dirhash_helper = None
        bb.debug(1, "go-dirhash-native not available, using pure Python for h1: checksums")

    def calculate_h1_hash_python(zip_path):
        """Calculate Go module h1: hash in pure Python."""
        lines = []
        with zipfile.ZipFile(zip_path, 'r') as zf:
            for info in sorted(zf.infolist(), key=lambda x: x.filename):
                if info.is_dir():
                    continue
                file_data = zf.read(info.filename)
                file_hash = hashlib.sha256(file_data).hexdigest()
                lines.append(f"{file_hash}  {info.filename}\n")
        summary = "".join(lines).encode('utf-8')
        final_hash = hashlib.sha256(summary).digest()
        return "h1:" + base64.b64encode(final_hash).decode('ascii')

    def calculate_h1_hash_native(zip_path):
        """Calculate Go module h1: hash using go-dirhash-native (fallback)."""
        if go_dirhash_helper is None:
            return None
        result = subprocess.run(
            [str(go_dirhash_helper), str(zip_path)],
            capture_output=True, text=True, check=False, timeout=60
        )
        if result.returncode != 0:
            return None
        hash_value = result.stdout.strip()
        if not hash_value.startswith("h1:"):
            return None
        return hash_value

    # Define helper functions BEFORE they are used
    def escape_module_path(path):
        """Escape capital letters using exclamation points (same as BitBake gomod.py)"""
        import re
        return re.sub(r'([A-Z])', lambda m: '!' + m.group(1).lower(), path)

    def sanitize_module_name(name):
        """Remove quotes from module names"""
        if not name:
            return name
        stripped = name.strip()
        if len(stripped) >= 2 and stripped[0] == '"' and stripped[-1] == '"':
            return stripped[1:-1]
        return stripped

    go_sum_hashes = {}
    go_sum_entries = {}
    go_sum_path = Path(d.getVar('S')) / "src" / "import" / "go.sum"
    if go_sum_path.exists():
        with open(go_sum_path, 'r') as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) != 3:
                    continue
                mod, ver, hash_value = parts
                mod = sanitize_module_name(mod)
                go_sum_entries[(mod, ver)] = hash_value
                if mod.endswith('/go.mod') or not hash_value.startswith('h1:'):
                    continue
                key = f"{mod}@{ver}"
                go_sum_hashes.setdefault(key, hash_value)

    def load_require_versions(go_mod_path):
        versions = {}
        if not go_mod_path.exists():
            return versions

        in_block = False
        with go_mod_path.open('r', encoding='utf-8') as f:
            for raw_line in f:
                line = raw_line.strip()

                if line.startswith('require ('):
                    in_block = True
                    continue
                if in_block and line == ')':
                    in_block = False
                    continue

                if line.startswith('require ') and '(' not in line:
                    parts = line.split()
                    if len(parts) >= 3:
                        versions[sanitize_module_name(parts[1])] = parts[2]
                    continue

                if in_block and line and not line.startswith('//'):
                    parts = line.split()
                    if len(parts) >= 2:
                        versions[sanitize_module_name(parts[0])] = parts[1]

        return versions

    def load_replacements(go_mod_path):
        replacements = {}
        if not go_mod_path.exists():
            return replacements

        def parse_replace_line(content):
            if '//' in content:
                content = content.split('//', 1)[0].strip()
            if '=>' not in content:
                return
            left, right = [part.strip() for part in content.split('=>', 1)]
            left_parts = left.split()
            right_parts = right.split()
            if not left_parts or not right_parts:
                return
            old_module = sanitize_module_name(left_parts[0])
            old_version = left_parts[1] if len(left_parts) > 1 else None
            new_module = sanitize_module_name(right_parts[0])
            new_version = right_parts[1] if len(right_parts) > 1 else None
            replacements[old_module] = {
                "old_version": old_version,
                "new_module": new_module,
                "new_version": new_version,
            }

        in_block = False
        with go_mod_path.open('r', encoding='utf-8') as f:
            for raw_line in f:
                line = raw_line.strip()

                if line.startswith('replace ('):
                    in_block = True
                    continue
                if in_block and line == ')':
                    in_block = False
                    continue

                if line.startswith('replace ') and '(' not in line:
                    parse_replace_line(line[len('replace '):])
                    continue

                if in_block and line and not line.startswith('//'):
                    parse_replace_line(line)

        return replacements

    go_mod_path = Path(d.getVar('S')) / "src" / "import" / "go.mod"
    require_versions = load_require_versions(go_mod_path)
    replacements = load_replacements(go_mod_path)

    def duplicate_module_version(module_path, source_version, alias_version, timestamp):
        if alias_version == source_version:
            return

        escaped_module = escape_module_path(module_path)
        cache_dir = Path(d.getVar('S')) / "pkg" / "mod" / "cache" / "download"
        download_dir = cache_dir / escaped_module / "@v"
        download_dir.mkdir(parents=True, exist_ok=True)

        escaped_source_version = escape_module_path(source_version)
        escaped_alias_version = escape_module_path(alias_version)

        source_base = download_dir / escaped_source_version
        alias_base = download_dir / escaped_alias_version

        if not (source_base.with_suffix('.zip').exists() and source_base.with_suffix('.mod').exists()):
            return

        if alias_base.with_suffix('.zip').exists():
            return

        import shutil
        shutil.copy2(source_base.with_suffix('.zip'), alias_base.with_suffix('.zip'))
        shutil.copy2(source_base.with_suffix('.mod'), alias_base.with_suffix('.mod'))
        ziphash_src = source_base.with_suffix('.ziphash')
        if ziphash_src.exists():
            shutil.copy2(ziphash_src, alias_base.with_suffix('.ziphash'))

        info_path = alias_base.with_suffix('.info')
        info_data = {
            "Version": alias_version,
            "Time": timestamp
        }
        with open(info_path, 'w') as f:
            json.dump(info_data, f)

        bb.note(f"Duplicated module version {module_path}@{alias_version} from {source_version} for replace directive")

    def create_module_zip(module_path, version, vcs_path, subdir, timestamp):
        """Create module zip file from git repository"""
        module_path = sanitize_module_name(module_path)

        # Detect canonical module path FIRST from go.mod.
        # This prevents creating duplicate cache entries for replace directives.
        # For "github.com/google/cadvisor => github.com/k3s-io/cadvisor", the
        # k3s-io fork declares "module github.com/google/cadvisor" in its go.mod,
        # so we create the cache ONLY at github.com/google/cadvisor.
        def detect_canonical_module_path(vcs_path, subdir_hint, requested_module):
            """
            Read go.mod file to determine the canonical module path.
            This is critical for replace directives - always use the path declared
            in the module's own go.mod, not the replacement path.
            """
            path = Path(vcs_path)

            # Build list of candidate subdirs to check
            candidates = []
            if subdir_hint:
                candidates.append(subdir_hint)

            # Also try deriving subdir from module path
            parts = requested_module.split('/')
            if len(parts) > 3:
                guess = '/'.join(parts[3:])
                if guess and guess not in candidates:
                    candidates.append(guess)

            # Always check root directory last
            if '' not in candidates:
                candidates.append('')

            # Search for go.mod file and read its module declaration
            for candidate in candidates:
                gomod_file = path / candidate / "go.mod" if candidate else path / "go.mod"
                if not gomod_file.exists():
                    continue

                try:
                    with gomod_file.open('r', encoding='utf-8') as fh:
                        first_line = fh.readline().strip()
                        # Parse: "module github.com/example/repo"
                        if first_line.startswith('module '):
                            canonical = first_line[7:].strip()  # Skip "module "
                            # Remove any inline comments
                            if '//' in canonical:
                                canonical = canonical.split('//')[0].strip()
                            # CRITICAL: Remove quotes from module names
                            canonical = sanitize_module_name(canonical)
                            return canonical, candidate
                except (UnicodeDecodeError, IOError):
                    continue

            # Fallback: if no go.mod found, use requested path
            # This is normal for some modules (e.g., pure Go stdlib-like packages)
            bb.note(f"No go.mod found for {requested_module} in {vcs_path}, using requested path")
            return requested_module, ''

        canonical_module_path, detected_subdir = detect_canonical_module_path(vcs_path, subdir, module_path)

        # Keep track of the original (requested) module path for replaced modules
        # We'll need to create symlinks from requested -> canonical after cache creation
        requested_module_path = module_path

        # If canonical path differs from requested path, this is a replace directive
        if canonical_module_path != module_path:
            bb.note(f"Replace directive detected: {module_path} -> canonical {canonical_module_path}")
            bb.note(f"Creating cache at canonical path, will symlink from requested path")
            module_path = canonical_module_path

        escaped_module = escape_module_path(module_path)
        escaped_version = escape_module_path(version)

        # Create cache directory structure using CANONICAL module path
        workdir = Path(d.getVar('WORKDIR'))
        s = Path(d.getVar('S'))
        cache_dir = s / "pkg" / "mod" / "cache" / "download"
        download_dir = cache_dir / escaped_module / "@v"
        download_dir.mkdir(parents=True, exist_ok=True)

        bb.note(f"Creating cache for {module_path}@{version}")

        # Override subdir with detected subdir from canonical path detection
        if detected_subdir:
            subdir = detected_subdir

        def detect_subdir() -> str:
            hinted = subdir or ""
            path = Path(vcs_path)

            def path_exists(rel: str) -> bool:
                if not rel:
                    return True
                return (path / rel).exists()

            candidate_order = []
            if hinted and hinted not in candidate_order:
                candidate_order.append(hinted)

            module_parts = module_path.split('/')
            if len(module_parts) > 3:
                guess = '/'.join(module_parts[3:])
                if guess and guess not in candidate_order:
                    candidate_order.append(guess)

            target_header = f"module {module_path}\n"
            found = None
            try:
                for go_mod in path.rglob('go.mod'):
                    rel = go_mod.relative_to(path)
                    if any(part.startswith('.') and part != '.' for part in rel.parts):
                        continue
                    if 'vendor' in rel.parts:
                        continue
                    try:
                        with go_mod.open('r', encoding='utf-8') as fh:
                            first_line = fh.readline()
                    except UnicodeDecodeError:
                        continue
                    if first_line.strip() == target_header.strip():
                        rel_dir = go_mod.parent.relative_to(path).as_posix()
                        found = rel_dir
                        break
            except Exception:
                pass

            if found is not None and found not in candidate_order:
                candidate_order.insert(0, found)

            candidate_order.append('')

            for candidate in candidate_order:
                if path_exists(candidate):
                    return candidate
            return ''

        subdir_resolved = detect_subdir()

        # 1. Create .info file
        info_path = download_dir / f"{escaped_version}.info"
        info_data = {
            "Version": version,
            "Time": timestamp
        }
        with open(info_path, 'w') as f:
            json.dump(info_data, f)
        bb.debug(1, f"Created {info_path}")

        # 2. Create .mod file
        mod_path = download_dir / f"{escaped_version}.mod"
        effective_subdir = subdir_resolved

        def candidate_subdirs():
            candidates = []
            parts = module_path.split('/')
            if len(parts) >= 4:
                extra = '/'.join(parts[3:])
                if extra:
                    candidates.append(extra)

            if effective_subdir:
                candidates.insert(0, effective_subdir)
            else:
                candidates.append('')

            suffix = parts[-1]
            if suffix.startswith('v') and suffix[1:].isdigit():
                suffix_path = f"{effective_subdir}/{suffix}" if effective_subdir else suffix
                if suffix_path not in candidates:
                    candidates.insert(0, suffix_path)

            if '' not in candidates:
                candidates.append('')
            return candidates

        gomod_file = None
        for candidate in candidate_subdirs():
            path_candidate = Path(vcs_path) / candidate / "go.mod" if candidate else Path(vcs_path) / "go.mod"
            if path_candidate.exists():
                gomod_file = path_candidate
                if candidate != effective_subdir:
                    effective_subdir = candidate
                break

        subdir_resolved = effective_subdir

        if gomod_file is None:
            gomod_file = Path(vcs_path) / effective_subdir / "go.mod" if effective_subdir else Path(vcs_path) / "go.mod"

        def synthesize_go_mod(modname, go_version=None):
            sanitized = sanitize_module_name(modname)
            if go_version:
                return f"module {sanitized}\n\ngo {go_version}\n".encode('utf-8')
            return f"module {sanitized}\n".encode('utf-8')

        mod_content = None

        def is_vendored_package(rel_path):
            if rel_path.startswith("vendor/"):
                prefix_len = len("vendor/")
            else:
                idx = rel_path.find("/vendor/")
                if idx < 0:
                    return False
                prefix_len = len("/vendor/")
            return "/" in rel_path[prefix_len:]

        if '+incompatible' in version:
            mod_content = synthesize_go_mod(module_path)
            bb.debug(1, f"Synthesizing go.mod for +incompatible module {module_path}@{version}")
        elif gomod_file.exists():
            # Read the existing go.mod and check if module declaration matches
            mod_content = gomod_file.read_bytes()

            # Parse the module declaration to check for mismatch
            import re
            match = re.search(rb'^\s*module\s+(\S+)', mod_content, re.MULTILINE)
            if match:
                declared_module = match.group(1).decode('utf-8', errors='ignore')
                if declared_module != module_path:
                    # Extract go version directive from original go.mod before synthesizing
                    go_version = None
                    go_match = re.search(rb'^\s*go\s+(\d+\.\d+(?:\.\d+)?)', mod_content, re.MULTILINE)
                    if go_match:
                        go_version = go_match.group(1).decode('utf-8', errors='ignore')
                    # Module declaration doesn't match import path - synthesize correct one
                    bb.note(f"Module {module_path}@{version}: go.mod declares '{declared_module}' but should be '{module_path}', synthesizing correct go.mod (preserving go {go_version})")
                    mod_content = synthesize_go_mod(module_path, go_version)
        else:
            bb.debug(1, f"go.mod not found at {gomod_file}")
            mod_content = synthesize_go_mod(module_path)

        with open(mod_path, 'wb') as f:
            f.write(mod_content)
        bb.debug(1, f"Created {mod_path}")

        license_blobs = []
        if effective_subdir:
            license_candidates = [
                "LICENSE",
                "LICENSE.txt",
                "LICENSE.md",
                "LICENCE",
                "COPYING",
                "COPYING.txt",
                "COPYING.md",
            ]
            for candidate in license_candidates:
                try:
                    content = subprocess.check_output(
                        ["git", "show", f"HEAD:{candidate}"],
                        cwd=vcs_path,
                        stderr=subprocess.DEVNULL,
                    )
                except subprocess.CalledProcessError:
                    continue
                license_blobs.append((Path(candidate).name, content))
                break

        # 3. Create .zip file using git archive + filtering
        zip_path = download_dir / f"{escaped_version}.zip"
        # IMPORTANT: For replaced modules, zip internal paths must use the REQUESTED module path,
        # not the canonical path. Go expects to unzip files to requested_module@version/ directory.
        zip_prefix = f"{requested_module_path}@{version}/"
        module_key = f"{module_path}@{version}"
        expected_hash = go_sum_hashes.get(module_key)

        import tarfile
        import tempfile

        # IMPORTANT: assemble_zip() must run INSIDE TemporaryDirectory context.
        # The add_zip_entry() and zipfile.ZipFile code MUST be indented inside the
        # 'with tempfile.TemporaryDirectory()' block. If placed outside, the temp
        # directory is deleted before files are added, resulting in empty zips.
        def assemble_zip(include_vendor_modules: bool) -> str:
            """
            Create module zip and compute h1: hash in single pass.
            Returns h1: hash string on success, None on failure.

            This avoids re-reading the zip file after creation by tracking
            file hashes during the zip creation process.
            """
            import base64

            try:
                with tempfile.TemporaryDirectory(dir=str(download_dir)) as tmpdir:
                    tar_path = Path(tmpdir) / "archive.tar"
                    archive_cmd = ["git", "archive", "--format=tar", "-o", str(tar_path), "HEAD"]
                    if subdir_resolved:
                        archive_cmd.append(subdir_resolved)

                    subprocess.run(archive_cmd, cwd=str(vcs_path), check=True, capture_output=True)

                    with tarfile.open(tar_path, 'r') as tf:
                        tf.extractall(tmpdir)
                    tar_path.unlink(missing_ok=True)

                    extract_root = Path(tmpdir)
                    if subdir_resolved:
                        extract_root = extract_root / subdir_resolved

                    excluded_prefixes = []
                    for gomod_file in extract_root.rglob("go.mod"):
                        rel_path = gomod_file.relative_to(extract_root).as_posix()
                        if rel_path != "go.mod":
                            prefix = gomod_file.parent.relative_to(extract_root).as_posix()
                            if prefix and not prefix.endswith("/"):
                                prefix += "/"
                            excluded_prefixes.append(prefix)

                    if zip_path.exists():
                        zip_path.unlink()

                    # Track file hashes for h1: calculation during zip creation
                    hash_entries = []  # List of (arcname, sha256_hex)

                    def add_zip_entry(zf, arcname, data, mode=None):
                        info = zipfile.ZipInfo(arcname)
                        info.date_time = (1980, 1, 1, 0, 0, 0)
                        info.compress_type = zipfile.ZIP_DEFLATED
                        info.create_system = 3  # Unix
                        if mode is None:
                            mode = stat.S_IFREG | 0o644
                        info.external_attr = ((mode & 0xFFFF) << 16)
                        zf.writestr(info, data)
                        # Track hash for h1: calculation
                        hash_entries.append((arcname, hashlib.sha256(data).hexdigest()))

                    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
                        for file_path in sorted(extract_root.rglob("*")):
                            if file_path.is_dir():
                                continue

                            rel_path = file_path.relative_to(extract_root).as_posix()

                            if file_path.is_symlink():
                                continue

                            if is_vendored_package(rel_path):
                                continue

                            if rel_path == "vendor/modules.txt" and not include_vendor_modules:
                                continue

                            if any(rel_path.startswith(prefix) for prefix in excluded_prefixes):
                                continue
                            if rel_path.endswith("go.mod") and rel_path != "go.mod":
                                continue

                            if rel_path == "go.mod":
                                data = mod_content
                                mode = stat.S_IFREG | 0o644
                            else:
                                data = file_path.read_bytes()
                                try:
                                    mode = file_path.stat().st_mode
                                except FileNotFoundError:
                                    mode = stat.S_IFREG | 0o644

                            add_zip_entry(zf, zip_prefix + rel_path, data, mode)

                        for license_name, content in license_blobs:
                            if (extract_root / license_name).exists():
                                continue
                            add_zip_entry(zf, zip_prefix + license_name, content, stat.S_IFREG | 0o644)

                    # Calculate h1: hash from tracked entries (sorted by filename)
                    hash_entries.sort(key=lambda x: x[0])
                    lines = [f"{h}  {name}\n" for name, h in hash_entries]
                    summary = "".join(lines).encode('utf-8')
                    final_hash = hashlib.sha256(summary).digest()
                    inline_hash = "h1:" + base64.b64encode(final_hash).decode('ascii')
                    return inline_hash

            except subprocess.CalledProcessError as e:
                bb.error(f"Failed to create zip for {module_path}@{version}: {e.stderr.decode()}")
                return None
            except Exception as e:
                bb.error(f"Failed to assemble zip for {module_path}@{version}: {e}")
                # Fallback: try native tool if zip was created but hash calculation failed
                if zip_path.exists():
                    fallback_hash = calculate_h1_hash_native(zip_path)
                    if fallback_hash:
                        bb.warn(f"Using go-dirhash-native fallback for {module_path}@{version}")
                        return fallback_hash
                return None

        hash_value = assemble_zip(include_vendor_modules=True)
        if hash_value is None:
            return None

        if expected_hash and hash_value and hash_value != expected_hash:
            bb.debug(1, f"Hash mismatch for {module_key} ({hash_value} != {expected_hash}), retrying without vendor/modules.txt")
            retry_hash = assemble_zip(include_vendor_modules=False)
            if retry_hash is None:
                return None
            hash_value = retry_hash

            if hash_value and hash_value != expected_hash:
                bb.note(f"{module_key} still mismatches expected hash after retry ({hash_value} != {expected_hash})")

        if hash_value:
            ziphash_path = download_dir / f"{escaped_version}.ziphash"
            with open(ziphash_path, 'w') as f:
                f.write(f"{hash_value}\n")
            bb.debug(1, f"Created {ziphash_path}")
        else:
            bb.warn(f"Skipping ziphash for {module_key} due to calculation errors")

        # 5. Extract zip to pkg/mod for offline builds
        # This step can be skipped if Go extracts on-demand from cache (experimental)
        skip_extraction = d.getVar('GO_MOD_SKIP_ZIP_EXTRACTION') == "1"
        if not skip_extraction:
            extract_dir = s / "pkg" / "mod"
            try:
                with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                    zip_ref.extractall(extract_dir)
                # Make extracted files writable so BitBake can clean them later
                # Go's module cache is read-only by design, but this breaks rm -rf
                escaped_modpath = escape_module_path(module_path)
                extracted_mod_dir = extract_dir / escaped_modpath / f"@{version}"
                if extracted_mod_dir.exists():
                    for root, dirs, files in os.walk(extracted_mod_dir):
                        for dir_name in dirs:
                            dir_path = Path(root) / dir_name
                            dir_path.chmod(dir_path.stat().st_mode | stat.S_IWUSR)
                        for file_name in files:
                            file_path = Path(root) / file_name
                            file_path.chmod(file_path.stat().st_mode | stat.S_IWUSR)
                    extracted_mod_dir.chmod(extracted_mod_dir.stat().st_mode | stat.S_IWUSR)
                bb.debug(1, f"Extracted {module_path}@{version} to {extract_dir}")
            except Exception as e:
                bb.error(f"Failed to extract {module_path}@{version}: {e}")
                return None

        # 6. If this was a replaced module, create symlinks from requested path to canonical path
        # This ensures Go can find the module by either name
        if requested_module_path != module_path:
            import os
            escaped_requested = escape_module_path(requested_module_path)
            requested_download_dir = cache_dir / escaped_requested / "@v"
            requested_download_dir.mkdir(parents=True, exist_ok=True)

            # Create symlinks for all cache files (.info, .mod, .zip, .ziphash)
            for suffix in ['.info', '.mod', '.zip', '.ziphash']:
                canonical_file = download_dir / f"{escaped_version}{suffix}"
                requested_file = requested_download_dir / f"{escaped_version}{suffix}"

                if canonical_file.exists() and not requested_file.exists():
                    try:
                        # Calculate relative path from requested to canonical
                        rel_path = os.path.relpath(canonical_file, requested_file.parent)
                        os.symlink(rel_path, requested_file)
                        bb.debug(1, f"Created symlink: {requested_file} -> {rel_path}")
                    except Exception as e:
                        bb.warn(f"Failed to create symlink for {requested_module_path}: {e}")

            bb.note(f"Created symlinks for replaced module: {requested_module_path} -> {module_path}")

        # Return the canonical module path for post-processing (e.g., duplicate version handling)
        return module_path

    def regenerate_go_sum():
        s_path = Path(d.getVar('S'))
        cache_dir = s_path / "pkg" / "mod" / "cache" / "download"
        go_sum_path = s_path / "src" / "import" / "go.sum"

        if not cache_dir.exists():
            bb.warn("Module cache directory not found - skipping go.sum regeneration")
            return

        def calculate_zip_checksum(zip_file):
            """Calculate h1: hash for a module zip file (pure Python with native fallback)"""
            try:
                result = calculate_h1_hash_python(zip_file)
                if result:
                    return result
            except Exception as e:
                bb.debug(1, f"Python hash failed for {zip_file}: {e}")

            # Fallback to native tool
            fallback = calculate_h1_hash_native(zip_file)
            if fallback:
                return fallback

            bb.warn(f"Failed to calculate zip checksum for {zip_file}")
            return None

        def calculate_mod_checksum(mod_path):
            try:
                mod_bytes = mod_path.read_bytes()
            except FileNotFoundError:
                return None

            import base64

            file_hash = hashlib.sha256(mod_bytes).hexdigest()
            summary = f"{file_hash}  go.mod\n".encode('ascii')
            digest = hashlib.sha256(summary).digest()
            return "h1:" + base64.b64encode(digest).decode('ascii')

        def unescape(value):
            import re

            return re.sub(r'!([a-z])', lambda m: m.group(1).upper(), value)

        existing_entries = {}

        if go_sum_path.exists():
            with open(go_sum_path, 'r') as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) != 3:
                        continue
                    mod, ver, hash_value = parts
                    mod = sanitize_module_name(mod)
                    existing_entries[(mod, ver)] = hash_value

        new_entries = {}

        for zip_file in sorted(cache_dir.rglob("*.zip")):
            zip_hash = calculate_zip_checksum(zip_file)
            if not zip_hash:
                continue

            parts = zip_file.parts
            try:
                v_index = parts.index('@v')
                download_index = parts.index('download')
            except ValueError:
                bb.warn(f"Unexpected cache layout for {zip_file}")
                continue

            escaped_module_parts = parts[download_index + 1:v_index]
            escaped_module = '/'.join(escaped_module_parts)
            escaped_version = zip_file.stem

            module_path = unescape(escaped_module)
            version = unescape(escaped_version)

            new_entries[(module_path, version)] = zip_hash

            mod_checksum = calculate_mod_checksum(zip_file.with_suffix('.mod'))
            if mod_checksum:
                new_entries[(module_path, f"{version}/go.mod")] = mod_checksum

        if not new_entries and not existing_entries:
            bb.warn("No go.sum entries available - skipping regeneration")
            return

        final_entries = existing_entries.copy()
        final_entries.update(new_entries)

        go_sum_path.parent.mkdir(parents=True, exist_ok=True)
        with open(go_sum_path, 'w') as f:
            for (mod, ver) in sorted(final_entries.keys()):
                f.write(f"{mod} {ver} {final_entries[(mod, ver)]}\n")

        bb.debug(1, f"Regenerated go.sum with {len(final_entries)} entries")

    # Process modules sequentially - I/O bound workload, parallelization causes disk thrashing
    workdir = Path(d.getVar('WORKDIR'))
    modules_data = json.loads(d.getVar('GO_MODULE_CACHE_DATA'))

    # Pure hybrid mode (all gomod://, no VCS modules) - nothing to do
    if not modules_data:
        bb.note("No VCS modules to process (pure hybrid mode) - skipping cache creation")
        return

    # Remove go.sum files from git-fetched dependencies to prevent checksum conflicts
    # The module checksums from git sources differ from the proxy checksums, and stale
    # go.sum files in dependencies can cause "checksum mismatch" errors during build
    vcs_cache_dir = workdir / "sources" / "vcs_cache"
    if vcs_cache_dir.exists():
        import subprocess
        result = subprocess.run(
            ['find', str(vcs_cache_dir), '-name', 'go.sum', '-delete'],
            capture_output=True, text=True
        )
        bb.debug(1, "Removed go.sum files from vcs_cache to prevent checksum conflicts")

    bb.note(f"Building module cache for {len(modules_data)} modules")

    # Track results from processing
    results = []  # List of (module_info, success, actual_module_path)
    success_count = 0
    fail_count = 0

    for i, module in enumerate(modules_data, 1):
        vcs_hash = module['vcs_hash']
        vcs_path = workdir / "sources" / "vcs_cache" / vcs_hash

        # Create module cache files
        actual_module_path = create_module_zip(
            module['module'],
            module['version'],
            vcs_path,
            module.get('subdir', ''),
            module['timestamp'],
        )

        if actual_module_path is not None:
            success_count += 1
            results.append((module, True, actual_module_path))
        else:
            fail_count += 1
            results.append((module, False, None))

        # Progress update every 100 modules
        if i % 100 == 0:
            bb.note(f"Progress: {i}/{len(modules_data)} modules processed")

    bb.note(f"Module processing complete: {success_count} succeeded, {fail_count} failed")

    # Post-processing: handle duplicate versions for replace directives (must be sequential)
    for module_info, success, actual_module_path in results:
        if success and actual_module_path:
            alias_info = replacements.get(actual_module_path)
            if alias_info:
                alias_version = alias_info.get("old_version") or require_versions.get(actual_module_path)
                if alias_version is None:
                    for (mod, ver), _hash in go_sum_entries.items():
                        if mod == actual_module_path and not ver.endswith('/go.mod'):
                            alias_version = ver
                            break
                if alias_version and alias_version != module_info['version']:
                    duplicate_module_version(actual_module_path, module_info['version'], alias_version, module_info['timestamp'])

    if fail_count == 0:
        regenerate_go_sum()
    else:
        bb.warn("Skipping go.sum regeneration due to module cache failures")

    bb.note(f"Module cache complete: {success_count} succeeded, {fail_count} failed")

    if fail_count > 0:
        bb.fatal(f"Failed to create cache for {fail_count} modules")
}

addtask create_module_cache after do_unpack do_prepare_recipe_sysroot before do_configure


python do_sync_go_files() {
    """
    Synchronize go.mod and go.sum with the module cache we built from git sources.

    This task solves the "go: updates to go.mod needed" error by ensuring go.mod
    declares ALL modules present in our module cache, and go.sum has checksums
    matching our git-built modules.

    Architecture: Option 2 (Rewrite go.mod/go.sum approach)
    - Scans pkg/mod/cache/download/ for ALL modules we built
    - Regenerates go.mod with complete require block
    - Regenerates go.sum with our h1: checksums from .ziphash files
    """
    import json
    import hashlib
    import re
    from pathlib import Path

    bb.note("Synchronizing go.mod and go.sum with module cache")

    s = Path(d.getVar('S'))
    cache_dir = s / "pkg" / "mod" / "cache" / "download"
    go_mod_path = s / "src" / "import" / "go.mod"
    go_sum_path = s / "src" / "import" / "go.sum"

    if not cache_dir.exists():
        bb.fatal("Module cache directory not found - run do_create_module_cache first")

    def unescape(escaped):
        """Unescape capital letters (reverse of escape_module_path)"""
        import re
        return re.sub(r'!([a-z])', lambda m: m.group(1).upper(), escaped)

    def sanitize_module_name(name):
        """Remove surrounding quotes added by legacy tools"""
        if not name:
            return name
        stripped = name.strip()
        if len(stripped) >= 2 and stripped[0] == '"' and stripped[-1] == '"':
            return stripped[1:-1]
        return stripped

    def load_require_versions(go_mod_path):
        versions = {}
        if not go_mod_path.exists():
            return versions

        in_block = False
        with go_mod_path.open('r', encoding='utf-8') as f:
            for raw_line in f:
                line = raw_line.strip()

                if line.startswith('require ('):
                    in_block = True
                    continue
                if in_block and line == ')':
                    in_block = False
                    continue

                if line.startswith('require ') and '(' not in line:
                    parts = line.split()
                    if len(parts) >= 3:
                        versions[sanitize_module_name(parts[1])] = parts[2]
                    continue

                if in_block and line and not line.startswith('//'):
                    parts = line.split()
                    if len(parts) >= 2:
                        versions[sanitize_module_name(parts[0])] = parts[1]

        return versions

    def load_replacements(go_mod_path):
        replacements = {}
        if not go_mod_path.exists():
            return replacements

        def parse_replace_line(line):
            if '//' in line:
                line = line.split('//', 1)[0].strip()
            if not line or '=>' not in line:
                return
            left, right = [part.strip() for part in line.split('=>', 1)]
            left_parts = left.split()
            right_parts = right.split()
            if not left_parts or not right_parts:
                return
            old_module = sanitize_module_name(left_parts[0])
            old_version = left_parts[1] if len(left_parts) > 1 else None
            new_module = sanitize_module_name(right_parts[0])
            new_version = right_parts[1] if len(right_parts) > 1 else None
            replacements[old_module] = {
                "old_version": old_version,
                "new_module": new_module,
                "new_version": new_version,
            }

        in_block = False
        with go_mod_path.open('r', encoding='utf-8') as f:
            for raw_line in f:
                line = raw_line.strip()

                if line.startswith('replace ('):
                    in_block = True
                    continue
                if in_block and line == ')':
                    in_block = False
                    continue

                if line.startswith('replace ') and '(' not in line:
                    parse_replace_line(line[len('replace '):])
                    continue

                if in_block and line and not line.startswith('//'):
                    parse_replace_line(line)

        return replacements

    require_versions = load_require_versions(go_mod_path)
    replacements = load_replacements(go_mod_path)

    # 1. Scan module cache to discover ALL modules we built
    # Map: (module_path, version) -> {"zip_checksum": str, "mod_path": Path}
    our_modules = {}

    bb.note("Scanning module cache...")
    for zip_file in sorted(cache_dir.rglob("*.zip")):
        parts = zip_file.parts
        try:
            v_index = parts.index('@v')
            download_index = parts.index('download')
        except ValueError:
            continue

        escaped_module_parts = parts[download_index + 1:v_index]
        escaped_module = '/'.join(escaped_module_parts)
        escaped_version = zip_file.stem

        module_path = unescape(escaped_module)
        module_path = sanitize_module_name(module_path)
        version = unescape(escaped_version)

        # Read checksum from .ziphash file
        ziphash_file = zip_file.with_suffix('.ziphash')
        if ziphash_file.exists():
            checksum = ziphash_file.read_text().strip()
            # Some .ziphash files have literal \\n at the end - remove it
            if checksum.endswith('\\\\n'):
                checksum = checksum[:-2]
            our_modules[(module_path, version)] = {
                "zip_checksum": checksum,
                "mod_path": zip_file.with_suffix('.mod'),
            }

    if not our_modules:
        bb.note("No VCS modules in cache (pure hybrid mode) - skipping go.mod/go.sum sync")
        return

    bb.note(f"Found {len(our_modules)} modules in cache")

    # 2. DO NOT modify go.mod - keep the original module declarations
    # The real problem is go.sum has wrong checksums (proxy vs git), not missing modules
    bb.note("Leaving go.mod unchanged - only updating go.sum with git-based checksums")

    # 3. Read original go.sum to preserve entries for modules not in our cache
    original_sum_entries = {}
    if go_sum_path.exists():
        for line in go_sum_path.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) >= 3:
                module = sanitize_module_name(parts[0])
                version = parts[1]
                checksum = parts[2]
                original_sum_entries[(module, version)] = checksum

    # 4. Build new go.sum by updating checksums for modules we built
    sum_entries_dict = original_sum_entries.copy()  # Start with original

    for (module, version), entry in our_modules.items():
        # Update .zip checksum
        sum_entries_dict[(module, version)] = entry["zip_checksum"]

        # Also update /go.mod entry if we have .mod file
        mod_file = entry["mod_path"]
        if mod_file.exists():
            # Calculate h1: checksum for .mod file
            mod_bytes = mod_file.read_bytes()
            file_hash = hashlib.sha256(mod_bytes).hexdigest()
            summary = f"{file_hash}  go.mod\n".encode('ascii')
            h1_bytes = hashlib.sha256(summary).digest()
            mod_checksum = "h1:" + __import__('base64').b64encode(h1_bytes).decode('ascii')
            sum_entries_dict[(module, f"{version}/go.mod")] = mod_checksum

    # 5. Duplicate checksums for modules that use replace directives so the original
    # module path (e.g., github.com/Mirantis/...) keeps matching go.sum entries.
    for alias_module, repl in replacements.items():
        alias_module = sanitize_module_name(alias_module)
        alias_version = repl.get("old_version")
        if alias_version is None:
            alias_version = require_versions.get(alias_module)
        if alias_version is None:
            # If go.mod didn't pin a replacement version, derive from go.sum
            for (mod, version) in list(original_sum_entries.keys()):
                if mod == alias_module and not version.endswith('/go.mod'):
                    alias_version = version
                    break
        if not alias_version:
            continue

        target_module = repl.get("new_module")
        target_version = repl.get("new_version")
        if target_version is None:
            target_version = require_versions.get(target_module)
        if not target_module or not target_version:
            continue

        entry = our_modules.get((target_module, target_version))
        if not entry and alias_module != target_module:
            entry = our_modules.get((alias_module, target_version))
        if not entry:
            continue

        sum_entries_dict[(alias_module, alias_version)] = entry["zip_checksum"]

        mod_file = entry["mod_path"]
        if mod_file.exists():
            mod_bytes = mod_file.read_bytes()
            file_hash = hashlib.sha256(mod_bytes).hexdigest()
            summary = f"{file_hash}  go.mod\n".encode('ascii')
            h1_bytes = hashlib.sha256(summary).digest()
            mod_checksum = "h1:" + __import__('base64').b64encode(h1_bytes).decode('ascii')
            sum_entries_dict[(alias_module, f"{alias_version}/go.mod")] = mod_checksum

    # Write merged go.sum
    sum_lines = []
    for (module, version), checksum in sorted(sum_entries_dict.items()):
        sum_lines.append(f"{module} {version} {checksum}")

    go_sum_path.write_text('\n'.join(sum_lines) + '\n')
    bb.note(f"Updated go.sum: {len(sum_entries_dict)} total entries, {len(our_modules)} updated from cache")

    bb.note("go.mod and go.sum synchronized successfully")
}

addtask sync_go_files after do_create_module_cache before do_compile


go_mod_fix_module_cache_permissions() {
    # Go creates read-only files in the module cache by design.
    # Fix permissions after do_compile so do_rm_work can clean up.
    for modpath in "${S}/pkg/mod" "${S}/src/import/pkg/mod"; do
        if [ -d "$modpath" ]; then
            chmod -R u+w "$modpath" 2>/dev/null || true
        fi
    done
    if [ -d "${WORKDIR}/sources" ]; then
        find "${WORKDIR}/sources" -type d -name "mod" -path "*/pkg/mod" 2>/dev/null | while read modpath; do
            chmod -R u+w "$modpath" 2>/dev/null || true
        done
    fi
}
do_compile[postfuncs] += "go_mod_fix_module_cache_permissions"


python do_go_mod_recommend() {
    """
    Analyze VCS-fetched modules and recommend candidates for gomod:// conversion.

    This task delegates to oe-go-mod-fetcher-hybrid.py --recommend to avoid
    duplicating the analysis logic. The script handles:
    - Module size calculation from vcs_cache
    - Grouping by prefix (github.com/containerd, k8s.io, etc.)
    - Suggesting --git prefixes for VCS-priority modules
    - Generating conversion command lines

    Run with: bitbake <recipe> -c go_mod_recommend
    """
    import subprocess
    from pathlib import Path

    # Find the hybrid script in meta-virtualization layer
    layerdir = None
    for layer in d.getVar('BBLAYERS').split():
        if 'meta-virtualization' in layer:
            layerdir = layer
            break

    if not layerdir:
        bb.error("Could not find meta-virtualization layer in BBLAYERS")
        return

    scriptpath = Path(layerdir) / "scripts" / "oe-go-mod-fetcher-hybrid.py"
    if not scriptpath.exists():
        bb.error(f"Hybrid script not found at {scriptpath}")
        return

    # Get recipe directory and workdir
    recipedir = d.getVar('FILE_DIRNAME')
    workdir = d.getVar('WORKDIR')

    # Build command to run the hybrid script with --recommend
    cmd = [
        'python3', str(scriptpath),
        '--recipedir', recipedir,
        '--recommend'
    ]

    # Add workdir if vcs_cache exists there (for size calculations)
    vcs_cache = Path(workdir) / "sources" / "vcs_cache"
    if vcs_cache.exists():
        cmd.extend(['--workdir', workdir])

    bb.note(f"Running: {' '.join(cmd)}")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300  # 5 minute timeout
        )

        # Print stdout (the recommendations)
        if result.stdout:
            for line in result.stdout.splitlines():
                bb.plain(line)

        # Print any errors
        if result.stderr:
            for line in result.stderr.splitlines():
                bb.warn(line)

        if result.returncode != 0:
            bb.warn(f"Script exited with code {result.returncode}")

    except subprocess.TimeoutExpired:
        bb.error("Recommendation script timed out after 5 minutes")
    except Exception as e:
        bb.error(f"Failed to run recommendation script: {e}")

    # Always print the recipe configuration hint
    bb.plain("")
    bb.plain("=" * 80)
    bb.plain("RECIPE CONFIGURATION FOR SWITCHING MODES:")
    bb.plain("=" * 80)
    bb.plain("")
    bb.plain("  Add this to your recipe to enable switching between VCS and hybrid modes:")
    bb.plain("")
    bb.plain('  # GO_MOD_FETCH_MODE: "vcs" (all git://) or "hybrid" (gomod:// + git://)')
    bb.plain('  GO_MOD_FETCH_MODE ?= "vcs"')
    bb.plain("")
    bb.plain('  # VCS mode: all modules via git://')
    bb.plain('  include ${@ "go-mod-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}')
    bb.plain('  include ${@ "go-mod-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}')
    bb.plain("")
    bb.plain('  # Hybrid mode: gomod:// for most, git:// for selected')
    bb.plain('  include ${@ "go-mod-hybrid-gomod.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}')
    bb.plain('  include ${@ "go-mod-hybrid-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}')
    bb.plain('  include ${@ "go-mod-hybrid-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}')
    bb.plain("")
    bb.plain("  Then switch modes with: GO_MOD_FETCH_MODE = \"hybrid\" in local.conf")
    bb.plain("")
}

addtask go_mod_recommend after do_fetch
do_go_mod_recommend[nostamp] = "1"

# =============================================================================
# Go Module Cache Permission Fix
# =============================================================================
#
# Go's module cache creates read-only files by design. This prevents BitBake's
# do_unpack cleanup (cleandirs = ${S}) from removing the previous build's
# module cache, causing "Permission denied" errors.
#
# Solution: Add a prefunc to do_unpack that makes the module cache writable
# before BitBake tries to clean the directory.
#

python go_mod_fix_permissions() {
    """
    Fix Go module cache permissions before do_unpack cleanup.

    Go creates read-only files in pkg/mod to prevent accidental modification.
    BitBake's cleandirs tries to rm -rf ${S} before unpacking, which fails
    on these read-only files. This prefunc makes them writable first.
    """
    import os
    import stat
    from pathlib import Path

    s_dir = d.getVar('S')
    if not s_dir:
        return

    # Check for Go module cache in various locations
    mod_paths = [
        Path(s_dir) / 'pkg' / 'mod',
        Path(s_dir) / 'src' / 'import' / 'pkg' / 'mod',  # k3s-style layout
    ]

    for mod_cache in mod_paths:
        if mod_cache.exists():
            bb.note(f"Fixing Go module cache permissions: {mod_cache}")
            try:
                # Walk the tree and add write permission
                for root, dirs, files in os.walk(str(mod_cache)):
                    # Fix directory permissions first
                    for d_name in dirs:
                        d_path = os.path.join(root, d_name)
                        try:
                            current = os.stat(d_path).st_mode
                            os.chmod(d_path, current | stat.S_IWUSR)
                        except (OSError, PermissionError):
                            pass
                    # Fix file permissions
                    for f_name in files:
                        f_path = os.path.join(root, f_name)
                        try:
                            current = os.stat(f_path).st_mode
                            os.chmod(f_path, current | stat.S_IWUSR)
                        except (OSError, PermissionError):
                            pass
                bb.note(f"Fixed permissions on {mod_cache}")
            except Exception as e:
                bb.warn(f"Could not fix permissions on {mod_cache}: {e}")

    # Also check the WORKDIR for sources subdirectories
    workdir = d.getVar('WORKDIR')
    if workdir:
        sources_dir = Path(workdir) / 'sources'
        if sources_dir.exists():
            for source_subdir in sources_dir.iterdir():
                if source_subdir.is_dir():
                    for mod_subpath in ['pkg/mod', 'src/import/pkg/mod']:
                        mod_cache = source_subdir / mod_subpath
                        if mod_cache.exists():
                            bb.note(f"Fixing Go module cache permissions: {mod_cache}")
                            try:
                                for root, dirs, files in os.walk(str(mod_cache)):
                                    for d_name in dirs:
                                        d_path = os.path.join(root, d_name)
                                        try:
                                            current = os.stat(d_path).st_mode
                                            os.chmod(d_path, current | stat.S_IWUSR)
                                        except (OSError, PermissionError):
                                            pass
                                    for f_name in files:
                                        f_path = os.path.join(root, f_name)
                                        try:
                                            current = os.stat(f_path).st_mode
                                            os.chmod(f_path, current | stat.S_IWUSR)
                                        except (OSError, PermissionError):
                                            pass
                                bb.note(f"Fixed permissions on {mod_cache}")
                            except Exception as e:
                                bb.warn(f"Could not fix permissions on {mod_cache}: {e}")
}

# Run permission fix BEFORE do_unpack's cleandirs removes ${S}
do_unpack[prefuncs] += "go_mod_fix_permissions"
