# =============================================================================
# Python function to pre-install packages for multi-layer OCI
# =============================================================================
# This function runs before IMAGE_CMD:oci and installs packages to temp rootfs
# directories using Yocto's package manager classes. The shell code then copies
# from these pre-installed directories.

def oci_compute_layer_cache_key(d, layer_name, layer_type, layer_packages):
    """
    Compute a cache key for a layer based on its definition and package versions.

    The cache key is a SHA256 hash of:
    - Layer name and type
    - Sorted package list
    - Package versions from PKGDATA_DIR
    - Machine and architecture info

    Returns: (cache_key, cache_info) tuple where cache_info is human-readable
    """
    import hashlib
    import os
    import json

    packages = sorted(layer_packages.split())
    pkgdata_dir = d.getVar('PKGDATA_DIR')
    machine = d.getVar('MACHINE')
    tune_pkgarch = d.getVar('TUNE_PKGARCH')

    # Build cache key components
    cache_components = {
        'layer_name': layer_name,
        'layer_type': layer_type,
        'packages': packages,
        'machine': machine,
        'tune_pkgarch': tune_pkgarch,
        'pkg_versions': {}
    }

    # Get package versions from pkgdata
    for pkg in packages:
        pkg_info_file = os.path.join(pkgdata_dir, 'runtime', pkg)
        if os.path.exists(pkg_info_file):
            try:
                with open(pkg_info_file, 'r') as f:
                    for line in f:
                        if line.startswith('PKGV:'):
                            cache_components['pkg_versions'][pkg] = line.split(':', 1)[1].strip()
                            break
                        elif line.startswith(f'PKGV_{pkg}:'):
                            cache_components['pkg_versions'][pkg] = line.split(':', 1)[1].strip()
                            break
            except Exception:
                pass

    # Create deterministic JSON for hashing
    cache_json = json.dumps(cache_components, sort_keys=True)
    cache_key = hashlib.sha256(cache_json.encode()).hexdigest()[:16]

    # Human-readable info for logging
    pkg_vers = [f"{p}={cache_components['pkg_versions'].get(p, '?')}" for p in packages[:3]]
    if len(packages) > 3:
        pkg_vers.append(f"...+{len(packages)-3} more")
    cache_info = f"{layer_name}:{' '.join(pkg_vers)}"

    return cache_key, cache_info


def oci_check_layer_cache(d, cache_key, layer_name):
    """
    Check if a cached layer exists.

    Returns: path to cached layer rootfs if found, None otherwise
    """
    import os

    cache_dir = d.getVar('OCI_LAYER_CACHE_DIR')
    if not cache_dir:
        return None

    cached_path = os.path.join(cache_dir, f'{cache_key}-{layer_name}')
    marker_file = os.path.join(cached_path, '.oci-layer-cache')

    if os.path.isdir(cached_path) and os.path.exists(marker_file):
        return cached_path

    return None


def oci_cache_layer(d, cache_key, layer_name, layer_rootfs):
    """
    Save a layer rootfs to the cache.
    """
    import os
    import shutil
    import time

    cache_dir = d.getVar('OCI_LAYER_CACHE_DIR')
    if not cache_dir:
        return

    bb.utils.mkdirhier(cache_dir)

    cached_path = os.path.join(cache_dir, f'{cache_key}-{layer_name}')

    # Remove any existing cache for this key
    if os.path.exists(cached_path):
        shutil.rmtree(cached_path)

    # Copy layer rootfs to cache
    bb.note(f"OCI Cache: Saving layer '{layer_name}' to cache ({cache_key})")
    shutil.copytree(layer_rootfs, cached_path, symlinks=True)

    # Write cache marker with metadata
    marker_file = os.path.join(cached_path, '.oci-layer-cache')
    with open(marker_file, 'w') as f:
        f.write(f"cache_key={cache_key}\n")
        f.write(f"layer_name={layer_name}\n")
        f.write(f"created={time.strftime('%Y-%m-%dT%H:%M:%SZ')}\n")
        f.write(f"machine={d.getVar('MACHINE')}\n")


def oci_restore_layer_from_cache(d, cached_path, layer_rootfs):
    """
    Restore a layer rootfs from the cache.
    """
    import os
    import shutil

    # Ensure target directory exists and is empty
    if os.path.exists(layer_rootfs):
        shutil.rmtree(layer_rootfs)
    bb.utils.mkdirhier(layer_rootfs)

    # Copy cached content (excluding the cache marker)
    for item in os.listdir(cached_path):
        if item == '.oci-layer-cache':
            continue
        src = os.path.join(cached_path, item)
        dst = os.path.join(layer_rootfs, item)
        if os.path.isdir(src):
            shutil.copytree(src, dst, symlinks=True)
        else:
            shutil.copy2(src, dst)


python oci_multilayer_install_packages() {
    """
    Pre-install packages for each packages layer in OCI_LAYERS.

    Creates temp rootfs directories with packages installed using Yocto's PM.
    The shell IMAGE_CMD:oci then copies from these directories.

    Supports layer caching when OCI_LAYER_CACHE = "1" to speed up rebuilds.
    """
    import os
    import shutil

    layer_mode = d.getVar('OCI_LAYER_MODE') or 'single'
    if layer_mode != 'multi':
        bb.debug(1, "OCI: Not in multi-layer mode, skipping pre-install")
        return

    oci_layers = d.getVar('OCI_LAYERS') or ''
    if not oci_layers.strip():
        return

    workdir = d.getVar('WORKDIR')
    layer_rootfs_base = os.path.join(workdir, 'oci-layer-rootfs')

    # Clean up any previous layer rootfs directories
    if os.path.exists(layer_rootfs_base):
        shutil.rmtree(layer_rootfs_base)
    bb.utils.mkdirhier(layer_rootfs_base)

    # Check if caching is enabled
    cache_enabled = d.getVar('OCI_LAYER_CACHE') == '1'
    if cache_enabled:
        bb.note("OCI: Pre-installing packages for multi-layer mode (caching enabled)")
    else:
        bb.note("OCI: Pre-installing packages for multi-layer mode (caching disabled)")

    cache_hits = 0
    cache_misses = 0

    # Parse OCI_LAYERS and install packages for each packages layer
    layer_num = 0
    for layer_def in oci_layers.split():
        parts = layer_def.split(':')
        if len(parts) < 3:
            continue
        layer_name = parts[0]
        layer_type = parts[1]
        layer_content = ':'.join(parts[2:]).replace('+', ' ')

        if layer_type == 'packages':
            layer_num += 1
            layer_rootfs = os.path.join(layer_rootfs_base, f'layer-{layer_num}-{layer_name}')

            # Check cache if enabled
            if cache_enabled:
                cache_key, cache_info = oci_compute_layer_cache_key(d, layer_name, layer_type, layer_content)
                cached_path = oci_check_layer_cache(d, cache_key, layer_name)

                if cached_path:
                    bb.note(f"OCI Cache HIT: Layer '{layer_name}' ({cache_key})")
                    oci_restore_layer_from_cache(d, cached_path, layer_rootfs)
                    cache_hits += 1
                    # Store the path for the shell code to use
                    d.setVar(f'OCI_LAYER_{layer_num}_ROOTFS', layer_rootfs)
                    d.setVar(f'OCI_LAYER_{layer_num}_NAME', layer_name)
                    continue
                else:
                    bb.note(f"OCI Cache MISS: Layer '{layer_name}' ({cache_info})")
                    cache_misses += 1

            bb.note(f"OCI: Pre-installing layer {layer_num} '{layer_name}' to {layer_rootfs}")

            # Call the package installation function
            oci_install_layer_packages(d, layer_rootfs, layer_content, layer_name)

            # Cache the installed layer if caching is enabled
            if cache_enabled:
                oci_cache_layer(d, cache_key, layer_name, layer_rootfs)

            # Store the path for the shell code to use
            d.setVar(f'OCI_LAYER_{layer_num}_ROOTFS', layer_rootfs)
            d.setVar(f'OCI_LAYER_{layer_num}_NAME', layer_name)

    d.setVar('OCI_LAYER_COUNT', str(layer_num))

    if cache_enabled:
        bb.note(f"OCI: Pre-installed packages for {layer_num} layers (cache: {cache_hits} hits, {cache_misses} misses)")
    else:
        bb.note(f"OCI: Pre-installed packages for {layer_num} layers")
}

# Run the Python function before IMAGE_CMD:oci
do_image_oci[prefuncs] += "oci_multilayer_install_packages"

# Fix merged-usr whiteout issues in OCI layer
# When a directory becomes a symlink, umoci creates whiteouts inside it, but
# puts them after the symlink in the tar. Docker fails because it can't create
# files inside a symlink. This function replaces individual whiteouts with
# opaque whiteouts and fixes tar ordering.
oci_fix_merged_usr_whiteouts() {
    local image_dir="$1"
    local tag="$2"
    local needs_fix=false

    # Find the manifest for this tag
    local manifest_digest=$(jq -r '.manifests[] | select(.annotations["org.opencontainers.image.ref.name"] == "'"$tag"'") | .digest' "$image_dir/index.json" | sed 's/sha256://')
    if [ -z "$manifest_digest" ]; then
        bbdebug 1 "OCI fix: Could not find manifest for tag $tag"
        return 0
    fi

    # Get the last layer (newest, the one we just added)
    local layer_digest=$(jq -r '.layers[-1].digest' "$image_dir/blobs/sha256/$manifest_digest" | sed 's/sha256://')
    if [ -z "$layer_digest" ]; then
        bbdebug 1 "OCI fix: Could not find layer digest"
        return 0
    fi

    local layer_blob="$image_dir/blobs/sha256/$layer_digest"
    if [ ! -f "$layer_blob" ]; then
        bbdebug 1 "OCI fix: Layer blob not found: $layer_blob"
        return 0
    fi

    # Convert to absolute path before we cd elsewhere
    layer_blob=$(readlink -f "$layer_blob")
    image_dir=$(readlink -f "$image_dir")

    # Get tar listing with details to identify symlinks and whiteouts
    local layer_listing=$(tar -tvzf "$layer_blob" 2>/dev/null || true)
    local layer_files=$(tar -tzf "$layer_blob" 2>/dev/null || true)

    # Find directories that are symlinks but have whiteouts listed inside
    # Include merged-usr dirs (bin, sbin, lib) and var/* symlinks
    local dirs_to_fix=""
    for dir in bin sbin lib lib64 var/lock var/log var/run var/tmp; do
        # Check if $dir is a symlink in the tar (line starts with 'l')
        if echo "$layer_listing" | grep -q "^l.* ${dir} -> "; then
            # Check if there are whiteouts "inside" it
            if echo "$layer_files" | grep -q "^${dir}/\.wh\."; then
                bbnote "OCI fix: Found problematic whiteout pattern in $dir"
                dirs_to_fix="$dirs_to_fix $dir"
                needs_fix=true
            fi
        fi
    done

    if [ "$needs_fix" != "true" ]; then
        bbdebug 1 "OCI fix: No merged-usr whiteout issues detected"
        return 0
    fi

    bbnote "OCI fix: Fixing merged-usr whiteout ordering in layer"
    bbnote "OCI fix: Directories to fix:$dirs_to_fix"

    # Save current directory
    local orig_dir=$(pwd)

    # Create temp directory for fix
    local fix_dir=$(mktemp -d)
    local fixed_tar="$fix_dir/fixed-layer.tar"

    cd "$fix_dir"

    # Strategy: Simply remove the problematic whiteouts
    # The symlink itself will hide the base directory contents.
    # We don't need opaque whiteouts - they would hide ALL base content.

    # Build exclude pattern - whiteouts in symlinked dirs
    local exclude_pattern=""
    for dir in $dirs_to_fix; do
        exclude_pattern="${exclude_pattern}|^${dir}/\\.wh\\."
    done
    exclude_pattern="${exclude_pattern#|}"  # Remove leading |

    # Use Python to filter the tar - just remove problematic whiteouts
    python3 << PYEOF
import tarfile
import gzip
import re

src_blob = "$layer_blob"
dst_tar = "$fixed_tar"
exclude_re = re.compile(r'$exclude_pattern')

removed_count = 0

# Read source tar and filter out problematic whiteouts
with gzip.open(src_blob, 'rb') as gz:
    with tarfile.open(fileobj=gz, mode='r:') as src:
        with tarfile.open(dst_tar, 'w') as dst:
            for member in src.getmembers():
                # Skip whiteouts in dirs that became symlinks
                if exclude_re.match(member.name):
                    removed_count += 1
                    continue

                # Copy the member
                if member.isfile():
                    dst.addfile(member, src.extractfile(member))
                else:
                    dst.addfile(member)

print(f"Removed {removed_count} problematic whiteouts from layer")
PYEOF

    # Calculate diff_id (uncompressed digest) before compressing
    local new_diff_id=$(sha256sum "$fixed_tar" | cut -d' ' -f1)
    local old_diff_id=$(gunzip -c "$layer_blob" | sha256sum | cut -d' ' -f1)

    # Compress the fixed tar
    gzip -n -f "$fixed_tar"
    local fixed_blob="$fixed_tar.gz"

    # Calculate new digest (compressed)
    local new_digest=$(sha256sum "$fixed_blob" | cut -d' ' -f1)
    local new_size=$(stat -c%s "$fixed_blob")

    bbnote "OCI fix: New layer digest: sha256:$new_digest (was sha256:$layer_digest)"
    bbnote "OCI fix: New diff_id: sha256:$new_diff_id (was sha256:$old_diff_id)"

    # Replace the blob
    cp "$fixed_blob" "$image_dir/blobs/sha256/$new_digest"
    rm -f "$image_dir/blobs/sha256/$layer_digest"

    # Update manifest with new layer digest and size
    local manifest_file="$image_dir/blobs/sha256/$manifest_digest"
    jq --arg old "sha256:$layer_digest" --arg new "sha256:$new_digest" --argjson size "$new_size" \
        '(.layers[] | select(.digest == $old)) |= (.digest = $new | .size = $size)' \
        "$manifest_file" > "$manifest_file.new"
    mv "$manifest_file.new" "$manifest_file"

    # Get config digest from manifest and update diff_ids in config
    local config_digest=$(jq -r '.config.digest' "$manifest_file" | sed 's/sha256://')
    local config_file="$image_dir/blobs/sha256/$config_digest"

    bbnote "OCI fix: Updating config $config_digest"

    # Update the last diff_id in the config (our layer)
    # Use direct index replacement since we know which layer we fixed
    jq --arg new "sha256:$new_diff_id" \
        '.rootfs.diff_ids[-1] = $new' \
        "$config_file" > "$config_file.new"
    mv "$config_file.new" "$config_file"

    # Recalculate config digest
    local new_config_digest=$(sha256sum "$config_file" | cut -d' ' -f1)
    local new_config_size=$(stat -c%s "$config_file")

    if [ "$new_config_digest" != "$config_digest" ]; then
        mv "$config_file" "$image_dir/blobs/sha256/$new_config_digest"
        # Update manifest with new config digest
        jq --arg old "sha256:$config_digest" --arg new "sha256:$new_config_digest" --argjson size "$new_config_size" \
            '.config |= (if .digest == $old then .digest = $new | .size = $size else . end)' \
            "$manifest_file" > "$manifest_file.new"
        mv "$manifest_file.new" "$manifest_file"
    fi

    # Recalculate manifest digest
    local new_manifest_digest=$(sha256sum "$manifest_file" | cut -d' ' -f1)
    local new_manifest_size=$(stat -c%s "$manifest_file")

    if [ "$new_manifest_digest" != "$manifest_digest" ]; then
        mv "$manifest_file" "$image_dir/blobs/sha256/$new_manifest_digest"
        # Update index.json
        jq --arg old "sha256:$manifest_digest" --arg new "sha256:$new_manifest_digest" --argjson size "$new_manifest_size" \
            '(.manifests[] | select(.digest == $old)) |= (.digest = $new | .size = $size)' \
            "$image_dir/index.json" > "$image_dir/index.json.new"
        mv "$image_dir/index.json.new" "$image_dir/index.json"
    fi

    # Restore original directory and cleanup
    cd "$orig_dir"
    rm -rf "$fix_dir"

    bbnote "OCI fix: Layer whiteout fix complete"
}

IMAGE_CMD:oci() {
    umoci_options=""

    bbdebug 1 "UMOCI image settings:"
    bbdebug 1 "  author: ${OCI_IMAGE_AUTHOR}"
    bbdebug 1 "  author email: ${OCI_IMAGE_AUTHOR_EMAIL}"
    bbdebug 1 "  tag: ${OCI_IMAGE_TAG}"
    bbdebug 1 "  arch: ${OCI_IMAGE_ARCH}"
    bbdebug 1 "  subarch: ${OCI_IMAGE_SUBARCH}"
    bbdebug 1 "  entrypoint: ${OCI_IMAGE_ENTRYPOINT}"
    bbdebug 1 "  entrypoint args: ${OCI_IMAGE_ENTRYPOINT_ARGS}"
    bbdebug 1 "  labels: ${OCI_IMAGE_LABELS}"
    bbdebug 1 "  uid: ${OCI_IMAGE_RUNTIME_UID}"
    bbdebug 1 "  working dir: ${OCI_IMAGE_WORKINGDIR}"
    bbdebug 1 "  env vars: ${OCI_IMAGE_ENV_VARS}"
    bbdebug 1 "  ports: ${OCI_IMAGE_PORTS}"

    # Auto-generate OCI standard labels at task time (not parse time)
    OCI_AUTO_LABELS=""
    if [ "${OCI_IMAGE_AUTO_LABELS}" = "1" ]; then
        # Git revision
        if [ -n "${OCI_IMAGE_REVISION}" ] && [ "${OCI_IMAGE_REVISION}" != "none" ]; then
            OCI_AUTO_LABELS="$OCI_AUTO_LABELS org.opencontainers.image.revision=${OCI_IMAGE_REVISION}"
        elif [ "${OCI_IMAGE_REVISION}" != "none" ]; then
            _rev=$(cd ${TOPDIR} && git rev-parse --short HEAD 2>/dev/null || true)
            [ -n "$_rev" ] && OCI_AUTO_LABELS="$OCI_AUTO_LABELS org.opencontainers.image.revision=$_rev"
        fi

        # Git branch
        if [ -n "${OCI_IMAGE_BRANCH}" ] && [ "${OCI_IMAGE_BRANCH}" != "none" ]; then
            OCI_AUTO_LABELS="$OCI_AUTO_LABELS org.opencontainers.image.ref.name=${OCI_IMAGE_BRANCH}"
        elif [ "${OCI_IMAGE_BRANCH}" != "none" ]; then
            _branch=$(cd ${TOPDIR} && git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
            [ -n "$_branch" ] && [ "$_branch" != "HEAD" ] && \
                OCI_AUTO_LABELS="$OCI_AUTO_LABELS org.opencontainers.image.ref.name=$_branch"
        fi

        # Build date (ISO 8601)
        if [ -n "${OCI_IMAGE_BUILD_DATE}" ] && [ "${OCI_IMAGE_BUILD_DATE}" != "none" ]; then
            OCI_AUTO_LABELS="$OCI_AUTO_LABELS org.opencontainers.image.created=${OCI_IMAGE_BUILD_DATE}"
        elif [ "${OCI_IMAGE_BUILD_DATE}" != "none" ]; then
            _date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            OCI_AUTO_LABELS="$OCI_AUTO_LABELS org.opencontainers.image.created=$_date"
        fi

        bbdebug 1 "  auto-labels: $OCI_AUTO_LABELS"
    fi

    OCI_REUSE_IMAGE=""

    # Change into the image deploy dir to avoid having any output operations capture
    # long directories or the location.
    cd ${IMGDEPLOYDIR}

    new_image=t
    image_name="${IMAGE_NAME}${IMAGE_NAME_SUFFIX}-oci"
    image_bundle_name="${IMAGE_NAME}${IMAGE_NAME_SUFFIX}-oci-bundle"
    if [ -n "$OCI_REUSE_IMAGE" ]; then
	if [ -d $image_name ]; then
	    bbdebug 1 "OCI: reusing image directory"
	    new_image=""
	fi
    else
	bbdebug 1 "OCI: removing existing container image directory"
	rm -rf $image_name $image_bundle_name
    fi

    if [ -z "${OCI_IMAGE_TAG}" ]; then
	OCI_IMAGE_TAG="initial-tag"
    fi

    # ========================================================================
    # PHASE 1: Initialize OCI layout (from scratch or from base image)
    # ========================================================================
    if [ -n "${_OCI_BASE_RECIPE}" ] || [ -n "${_OCI_BASE_PATH}" ]; then
        # Using a base image
        base_oci_dir=""
        base_tag="${OCI_BASE_IMAGE_TAG}"

        if [ -n "${_OCI_BASE_RECIPE}" ]; then
            # Use exact symlink naming: ${recipe}-${tag}-oci
            base_oci_dir="${DEPLOY_DIR_IMAGE}/${_OCI_BASE_RECIPE}-${base_tag}-oci"

            if [ ! -d "$base_oci_dir" ] || [ ! -f "$base_oci_dir/index.json" ]; then
                bbfatal "OCI: Base image '${_OCI_BASE_RECIPE}' not found at expected path: $base_oci_dir"
            fi
        elif [ -n "${_OCI_BASE_PATH}" ]; then
            base_oci_dir="${_OCI_BASE_PATH}"
            if [ ! -d "$base_oci_dir" ] || [ ! -f "$base_oci_dir/index.json" ]; then
                bbfatal "OCI: Base image path not valid: $base_oci_dir"
            fi
        fi

        # Resolve symlinks to get actual directory
        base_oci_dir=$(readlink -f "$base_oci_dir")
        bbnote "OCI: Using base image from: $base_oci_dir"

        # Copy base image layout to our image directory (-L to follow symlinks)
        cp -rL "$base_oci_dir" "$image_name"

        # Count existing layers for logging (simplified)
        base_layers=$(ls "$image_name/blobs/sha256/" 2>/dev/null | wc -l)
        bbnote "OCI: Base image has approximately $base_layers blob(s)"

        # Unpack base image for modification
        umoci unpack --rootless --image "$image_name:$base_tag" "$image_bundle_name"
    elif [ -n "$new_image" ]; then
        # No base image - create empty OCI layout
        bbdebug 1 "OCI: umoci init --layout $image_name"
        umoci init --layout $image_name
        umoci new --image $image_name:${OCI_IMAGE_TAG}
        umoci unpack --rootless --image $image_name:${OCI_IMAGE_TAG} $image_bundle_name
    else
        # todo: create a different tag, after checking if the passed one exists
        true
    fi

    # ========================================================================
    # PHASE 2: Add content layer(s)
    # ========================================================================
    bbdebug 1 "OCI: populating rootfs"

    # Determine which tag to use for repack
    repack_tag="${OCI_IMAGE_TAG}"
    if [ -n "${_OCI_BASE_RECIPE}" ] || [ -n "${_OCI_BASE_PATH}" ]; then
        repack_tag="${OCI_BASE_IMAGE_TAG}"
    fi

    if [ "${OCI_LAYER_MODE}" = "multi" ]; then
        # ==================================================================
        # Multi-layer mode: Use pre-installed layer rootfs from Python
        # ==================================================================
        # The Python prefunc oci_multilayer_install_packages() has already
        # installed packages to temp rootfs directories using Yocto's PM classes.
        # We just need to copy from those directories and repack each layer.

        bbnote "OCI: Using multi-layer mode (packages pre-installed by Python PM classes)"

        # Process each layer from OCI_LAYERS
        oci_layer_num=0
        oci_pkg_layer_num=0
        oci_total_layers=0
        for oci_tmp in ${OCI_LAYERS}; do
            oci_total_layers=`expr $oci_total_layers + 1`
        done

        for oci_layer_def in ${OCI_LAYERS}; do
            oci_layer_num=`expr $oci_layer_num + 1`
            oci_layer_name=$(echo "$oci_layer_def" | cut -d: -f1)
            oci_layer_type=$(echo "$oci_layer_def" | cut -d: -f2)
            oci_layer_content=$(echo "$oci_layer_def" | cut -d: -f3- | tr '+' ' ')

            bbnote "OCI: Processing layer $oci_layer_num/$oci_total_layers: $oci_layer_name ($oci_layer_type)"

            if [ "$oci_layer_type" = "packages" ]; then
                # Packages were pre-installed by Python. Copy from temp rootfs.
                oci_pkg_layer_num=`expr $oci_pkg_layer_num + 1`
                oci_preinstall_rootfs="${WORKDIR}/oci-layer-rootfs/layer-${oci_pkg_layer_num}-${oci_layer_name}"

                if [ -d "$oci_preinstall_rootfs" ]; then
                    bbnote "OCI: Copying pre-installed packages from $oci_preinstall_rootfs"
                    # Use rsync to merge into bundle rootfs (handles symlinks properly)
                    rsync -a --no-owner --no-group "$oci_preinstall_rootfs/" "$image_bundle_name/rootfs/"

                    # Create usrmerge symlinks in the first packages layer.
                    # Normally done by ROOTFS_PREPROCESS_COMMAND in do_rootfs,
                    # which doesn't run for multi-layer rootfs directories.
                    if [ "$oci_pkg_layer_num" = "1" ]; then
                        if ${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', 'true', 'false', d)}; then
                            bbnote "OCI: Creating usrmerge symlinks in first layer"
                            create_merged_usr_symlinks "$image_bundle_name/rootfs"
                        fi
                    fi
                else
                    bbwarn "OCI: Pre-installed rootfs not found at $oci_preinstall_rootfs"
                fi

            elif [ "$oci_layer_type" = "directories" ]; then
                # Copy directories from IMAGE_ROOTFS (delta-only: skip files already in bundle)
                for oci_dir in $oci_layer_content; do
                    if [ -d "${IMAGE_ROOTFS}$oci_dir" ]; then
                        oci_delta_copied=0
                        oci_delta_skipped=0
                        # Walk the directory and copy only files not in bundle
                        # Copy files (delta-only)
                        find "${IMAGE_ROOTFS}$oci_dir" \( -type f -o -type l \) | while IFS= read -r oci_src_file; do
                            oci_rel_path="${oci_src_file#${IMAGE_ROOTFS}}"
                            oci_dst_file="$image_bundle_name/rootfs$oci_rel_path"
                            if [ ! -e "$oci_dst_file" ]; then
                                mkdir -p "$(dirname "$oci_dst_file")"
                                cp -a --no-preserve=ownership "$oci_src_file" "$oci_dst_file"
                                oci_delta_copied=$(expr $oci_delta_copied + 1)
                            else
                                oci_delta_skipped=$(expr $oci_delta_skipped + 1)
                            fi
                        done
                        # Also copy empty directories
                        find "${IMAGE_ROOTFS}$oci_dir" -type d | while IFS= read -r oci_src_dir; do
                            oci_rel_path="${oci_src_dir#${IMAGE_ROOTFS}}"
                            oci_dst_dir="$image_bundle_name/rootfs$oci_rel_path"
                            if [ ! -e "$oci_dst_dir" ]; then
                                mkdir -p "$oci_dst_dir"
                            fi
                        done
                        bbnote "OCI: Added directory $oci_dir (delta: $oci_delta_copied copied, $oci_delta_skipped skipped)"
                    else
                        bbwarn "OCI: Directory not found in IMAGE_ROOTFS: $oci_dir"
                    fi
                done

            elif [ "$oci_layer_type" = "files" ]; then
                # Copy specific files from IMAGE_ROOTFS (delta-only: skip files already in bundle)
                for oci_file in $oci_layer_content; do
                    if [ -e "${IMAGE_ROOTFS}$oci_file" ]; then
                        oci_dst_file="$image_bundle_name/rootfs$oci_file"
                        if [ ! -e "$oci_dst_file" ]; then
                            mkdir -p "$(dirname "$oci_dst_file")"
                            cp -a --no-preserve=ownership "${IMAGE_ROOTFS}$oci_file" "$oci_dst_file"
                            bbnote "OCI: Added file $oci_file"
                        else
                            bbnote "OCI: Skipped file $oci_file (already in bundle)"
                        fi
                    else
                        bbwarn "OCI: File not found in IMAGE_ROOTFS: $oci_file"
                    fi
                done

            elif [ "$oci_layer_type" = "host" ]; then
                # Copy files from build machine filesystem (outside Yocto)
                # Format: source_path:dest_path pairs separated by + (already converted to space)
                for oci_host_pair in $oci_layer_content; do
                    # Split on last : to handle paths that might contain :
                    oci_host_src="${oci_host_pair%:*}"
                    oci_host_dst="${oci_host_pair##*:}"
                    if [ -e "$oci_host_src" ]; then
                        mkdir -p "$image_bundle_name/rootfs$(dirname $oci_host_dst)"
                        cp -a --no-preserve=ownership "$oci_host_src" "$image_bundle_name/rootfs$oci_host_dst"
                        bbnote "OCI: Added from host: $oci_host_src -> $oci_host_dst"
                    else
                        bbfatal "OCI: Host path not found: $oci_host_src"
                    fi
                done
            fi

            # Repack to create layer
            bbnote "OCI: Repacking layer $oci_layer_name"
            umoci repack --image "$image_name:$repack_tag" "$image_bundle_name"

            # Re-unpack for next layer if not the last one
            if [ "$oci_layer_num" -lt "$oci_total_layers" ]; then
                rm -rf "$image_bundle_name"
                umoci unpack --rootless --image "$image_name:$repack_tag" "$image_bundle_name"
            fi
        done

        bbnote "OCI: Created $oci_layer_num layers"

    else
        # ==================================================================
        # Single-layer mode: Copy entire rootfs as one layer
        # ==================================================================
        # Use rsync for robust merging when base image exists (handles symlink vs dir conflicts)
        # For no-base builds, cp is sufficient and faster
        # Note: When source has symlinks replacing dest directories, we first remove conflicting dirs
        if [ -n "${_OCI_BASE_RECIPE}" ] || [ -n "${_OCI_BASE_PATH}" ]; then
            # Handle Yocto's merged-usr symlinks (/bin -> /usr/bin) and /var symlinks
            # replacing Alpine's or other base image directories
            for p in bin lib lib64 sbin var/lock var/log var/tmp; do
                src="${IMAGE_ROOTFS}/$p"
                dst="$image_bundle_name/rootfs/$p"
                if [ -L "$src" ] && [ -d "$dst" ] && [ ! -L "$dst" ]; then
                    bbdebug 1 "OCI: removing directory $dst to replace with symlink"
                    rm -rf "$dst"
                fi
            done
            bbdebug 1 "OCI: rsync -a --no-owner --no-group ${IMAGE_ROOTFS}/ $image_bundle_name/rootfs/"
            rsync -a --no-owner --no-group ${IMAGE_ROOTFS}/ $image_bundle_name/rootfs/
        else
            bbdebug 1 "OCI: cp -r ${IMAGE_ROOTFS}/* $image_bundle_name/rootfs/"
            cp -r -a --no-preserve=ownership ${IMAGE_ROOTFS}/* $image_bundle_name/rootfs
        fi

        bbdebug 1 "OCI: umoci repack --image $image_name:$repack_tag $image_bundle_name"
        umoci repack --image $image_name:$repack_tag $image_bundle_name
    fi

    # If we used a base image with different tag, re-tag to our target tag
    if [ -n "${_OCI_BASE_RECIPE}" ] || [ -n "${_OCI_BASE_PATH}" ]; then
        if [ "$repack_tag" != "${OCI_IMAGE_TAG}" ]; then
            umoci tag --image "$image_name:$repack_tag" "${OCI_IMAGE_TAG}"
        fi

        # Log final layer count (simplified - count blobs minus config/manifest)
        final_blobs=$(ls "$image_name/blobs/sha256/" 2>/dev/null | wc -l)
        bbnote "OCI: Final image has approximately $final_blobs blob(s)"
    fi

    bbdebug 1 "OCI: configuring image"
    if [ -n "${OCI_IMAGE_LABELS}" ]; then
	for l in ${OCI_IMAGE_LABELS}; do
	    bbdebug 1 "OCI: umoci config --image $image_name:${OCI_IMAGE_TAG} --config.label \"$l\""
	    umoci config --image $image_name:${OCI_IMAGE_TAG} --config.label "$l"
	done
    fi
    # Apply auto-generated OCI standard labels
    if [ -n "$OCI_AUTO_LABELS" ]; then
	for l in $OCI_AUTO_LABELS; do
	    bbdebug 1 "OCI: umoci config --image $image_name:${OCI_IMAGE_TAG} --config.label \"$l\""
	    umoci config --image $image_name:${OCI_IMAGE_TAG} --config.label "$l"
	done
    fi
    if [ -n "${OCI_IMAGE_ENV_VARS}" ]; then
	for l in ${OCI_IMAGE_ENV_VARS}; do
	    bbdebug 1 "umoci config --image $image_name:${OCI_IMAGE_TAG} --config.env \"$l\""
	    umoci config --image $image_name:${OCI_IMAGE_TAG} --config.env "$l"
	done
    fi
    if [ -n "${OCI_IMAGE_PORTS}" ]; then
	for l in ${OCI_IMAGE_PORTS}; do
	    bbdebug 1 "umoci config --image $image_name:${OCI_IMAGE_TAG} --config.exposedports $l"
	    umoci config --image $image_name:${OCI_IMAGE_TAG} --config.exposedports $l
	done
    fi
    if [ -n "${OCI_IMAGE_RUNTIME_UID}" ]; then
	bbdebug 1 "umoci config --image $image_name:${OCI_IMAGE_TAG}  --config.user ${OCI_IMAGE_RUNTIME_UID}"
	umoci config --image $image_name:${OCI_IMAGE_TAG} --config.user ${OCI_IMAGE_RUNTIME_UID}
    fi
    if [ -n "${OCI_IMAGE_WORKINGDIR}" ]; then
	bbdebug 1 "umoci config --image $image_name:${OCI_IMAGE_TAG}  --config.workingdir ${OCI_IMAGE_WORKINGDIR}"
	umoci config --image $image_name:${OCI_IMAGE_TAG} --config.workingdir ${OCI_IMAGE_WORKINGDIR}
    fi
    if [ -n "${OCI_IMAGE_STOPSIGNAL}" ]; then
	bbdebug 1 "umoci config --image $image_name:${OCI_IMAGE_TAG}  --config.stopsignal ${OCI_IMAGE_STOPSIGNAL}"
	umoci config --image $image_name:${OCI_IMAGE_TAG} --config.stopsignal ${OCI_IMAGE_STOPSIGNAL}
    fi
    if [ -n "${OCI_IMAGE_OS}" ]; then
	bbdebug 1 "umoci config --image $image_name:${OCI_IMAGE_TAG}  --os ${OCI_IMAGE_OS}"
	umoci config --image $image_name:${OCI_IMAGE_TAG} --os ${OCI_IMAGE_OS}
    fi

    bbdebug 1 "umoci config --image $image_name:${OCI_IMAGE_TAG}  --architecture ${OCI_IMAGE_ARCH}"
    umoci config --image $image_name:${OCI_IMAGE_TAG} --architecture ${OCI_IMAGE_ARCH}
    # NOTE: umoci doesn't currently expose setting the architecture variant,
    #       so if you need it use sloci instead
    if [ -n "${OCI_IMAGE_SUBARCH}" ]; then
	bbnote "OCI: image subarch is set to: ${OCI_IMAGE_SUBARCH}, but umoci does not"
	bbnote "     expose variants. use sloci instead if this is important"
    fi
    # Set entrypoint if specified (for wrapper script patterns)
    if [ -n "${OCI_IMAGE_ENTRYPOINT}" ]; then
	umoci config --image $image_name:${OCI_IMAGE_TAG} \
	    ${@" ".join("--config.entrypoint '%s'" % s for s in __import__('shlex').split(d.getVar("OCI_IMAGE_ENTRYPOINT")))}
    fi
    # Set CMD: use OCI_IMAGE_ENTRYPOINT_ARGS if set (legacy), otherwise OCI_IMAGE_CMD
    if [ -n "${OCI_IMAGE_ENTRYPOINT_ARGS}" ]; then
	umoci config --image $image_name:${OCI_IMAGE_TAG} ${@" ".join("--config.cmd '%s'" % s for s in __import__('shlex').split(d.getVar("OCI_IMAGE_ENTRYPOINT_ARGS")))}
    elif [ -n "${OCI_IMAGE_CMD}" ]; then
	umoci config --image $image_name:${OCI_IMAGE_TAG} ${@" ".join("--config.cmd '%s'" % s for s in __import__('shlex').split(d.getVar("OCI_IMAGE_CMD")))}
    fi
    umoci config --image $image_name:${OCI_IMAGE_TAG} --author ${OCI_IMAGE_AUTHOR_EMAIL}

    # ========================================================================
    # PHASE 3: Fix merged-usr whiteout issues for non-merged-usr base images
    # ========================================================================
    # When layering merged-usr (symlinks) on traditional layout (directories),
    # umoci creates whiteouts like bin/.wh.file but puts them AFTER the bin symlink
    # in the tar. Docker can't create files inside a symlink, causing pull failures.
    # Fix: Replace individual whiteouts with opaque whiteouts, reorder tar entries.
    # NOTE: Must run AFTER all umoci config commands since they create new config blobs.
    if [ -n "${_OCI_BASE_RECIPE}" ] || [ -n "${_OCI_BASE_PATH}" ]; then
        oci_fix_merged_usr_whiteouts "$image_name" "${OCI_IMAGE_TAG}"
    fi

    # OCI_IMAGE_TAG may contain ":", but these are not allowed in OCI file
    # names so replace them
    image_tag="${@d.getVar("OCI_IMAGE_TAG").replace(":", "_")}"

    # make a tar version of the image direcotry
    #  1) image_name.tar: compatible with oci tar format, blobs and rootfs
    #     are at the top level. Can load directly from something like podman
    #  2) image_name-dir.tar: original format from meta-virt, is just a tar'd
    #     up oci image directory (compatible with skopeo :dir format)
    if [ -n "${OCI_IMAGE_TAR_OUTPUT}" ]; then
        (
	    cd "$image_name"
	    tar -cf ../"$image_name.tar" "."
	)
	tar -cf "$image_name-dir.tar" "$image_name"

	# create a convenience symlink
	# Use -n to avoid creating link inside existing symlink target directory
	ln -sfn "$image_name.tar" "${IMAGE_BASENAME}-$image_tag-oci.tar"
	ln -sfn "$image_name-dir.tar" "${IMAGE_BASENAME}-$image_tag-oci-dir.tar"
    fi

    # We could make this optional, since the bundle is directly runnable via runc
    rm -rf $image_bundle_name

    # This is the OCI image directory, which is technically the "image" as specified
    # Use -n to avoid creating link inside existing symlink target directory
    ln -sfn $image_name ${IMAGE_BASENAME}-$image_tag-oci
}
