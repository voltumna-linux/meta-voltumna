# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# oci-multiarch.bbclass
# ===========================================================================
# Build multi-architecture OCI container images locally
# ===========================================================================
#
# This class creates OCI Image Index (manifest list) from multiple
# single-architecture OCI images built via multiconfig.
#
# USAGE:
#   # In your recipe (e.g., myapp-container-multiarch.bb):
#   inherit oci-multiarch
#
#   OCI_MULTIARCH_RECIPE = "myapp-container"
#   OCI_MULTIARCH_PLATFORMS = "aarch64 x86_64"
#
#   # Optional: custom multiconfig mapping (defaults use vcontainer distro)
#   OCI_MULTIARCH_MC[aarch64] = "container-aarch64"
#   OCI_MULTIARCH_MC[x86_64] = "container-x86-64"
#
# OUTPUT:
#   ${DEPLOY_DIR_IMAGE}/${PN}-multiarch-oci/
#     index.json        - OCI Image Index with platform entries
#     oci-layout        - OCI layout marker
#     blobs/sha256/     - Combined blobs from all architectures
#
# REQUIREMENTS:
#   - Multiconfig must be enabled (meta-virt-host.conf provides defaults):
#       BBMULTICONFIG = "... container-aarch64 container-x86-64"
#   - OCI_MULTIARCH_RECIPE must inherit image-oci or produce OCI output
#
# ===========================================================================

inherit nopackages

INHIBIT_DEFAULT_DEPS = "1"

# Required variables
OCI_MULTIARCH_RECIPE ?= ""
OCI_MULTIARCH_PLATFORMS ?= ""

# Default multiconfig mapping (uses vcontainer distro -- no BBMASK)
OCI_MULTIARCH_MC[aarch64] ?= "container-aarch64"
OCI_MULTIARCH_MC[x86_64] ?= "container-x86-64"

# Machine mapping for deploy directory paths
OCI_MULTIARCH_MACHINE[aarch64] ?= "qemuarm64"
OCI_MULTIARCH_MACHINE[x86_64] ?= "qemux86-64"

# Architecture to OCI platform name mapping
OCI_ARCH_TO_PLATFORM[aarch64] = "arm64"
OCI_ARCH_TO_PLATFORM[x86_64] = "amd64"

# Output directory
OCI_MULTIARCH_OUTPUT = "${DEPLOY_DIR_IMAGE}/${PN}-multiarch-oci"

# Delete standard tasks we don't need
deltask do_fetch
deltask do_unpack
deltask do_patch
deltask do_configure
deltask do_compile
deltask do_install
deltask do_populate_lic
deltask do_populate_sysroot
deltask do_package
deltask do_package_qa
deltask do_packagedata

# Generate mcdepends at parse time
python __anonymous() {
    recipe = d.getVar('OCI_MULTIARCH_RECIPE')
    platforms = d.getVar('OCI_MULTIARCH_PLATFORMS')

    if not recipe:
        bb.fatal("OCI_MULTIARCH_RECIPE must be set")

    if not platforms:
        bb.fatal("OCI_MULTIARCH_PLATFORMS must be set (e.g., 'aarch64 x86_64')")

    # Build mcdepends string for each platform
    mcdepends = []
    for platform in platforms.split():
        mc = d.getVarFlag('OCI_MULTIARCH_MC', platform)
        if not mc:
            bb.fatal(f"No multiconfig defined for platform '{platform}'. Set OCI_MULTIARCH_MC[{platform}]")
        mcdepends.append(f"mc::{mc}:{recipe}:do_image_complete")

    # Set the mcdepends for our main task
    d.setVarFlag('do_create_multiarch_index', 'mcdepends', ' '.join(mcdepends))

    bb.note(f"OCI multi-arch: building {recipe} for platforms: {platforms}")
}

python do_create_multiarch_index() {
    import os
    import json
    import shutil
    import hashlib

    recipe = d.getVar('OCI_MULTIARCH_RECIPE')
    platforms = d.getVar('OCI_MULTIARCH_PLATFORMS').split()
    topdir = d.getVar('TOPDIR')
    output_dir = d.getVar('OCI_MULTIARCH_OUTPUT')

    bb.plain(f"Creating multi-arch OCI Image Index for {recipe}")
    bb.plain(f"Platforms: {' '.join(platforms)}")

    # Clean output directory
    if os.path.exists(output_dir):
        shutil.rmtree(output_dir)
    os.makedirs(os.path.join(output_dir, 'blobs', 'sha256'))

    # Collect manifests from each platform
    index_manifests = []

    for platform in platforms:
        mc = d.getVarFlag('OCI_MULTIARCH_MC', platform)
        machine = d.getVarFlag('OCI_MULTIARCH_MACHINE', platform)
        oci_platform = d.getVarFlag('OCI_ARCH_TO_PLATFORM', platform) or platform

        if not mc or not machine:
            bb.fatal(f"Missing configuration for platform {platform}")

        # Find the OCI image in the multiconfig's deploy directory
        # Pattern: tmp-<mc>/deploy/images/<machine>/<recipe>-latest-oci/
        mc_deploy_base = os.path.join(topdir, f'tmp-{mc}', 'deploy', 'images', machine)

        # Try different naming patterns
        oci_patterns = [
            f"{recipe}-latest-oci",
            f"{recipe}-{machine}-latest-oci",
            f"{recipe}-oci",
        ]

        oci_dir = None
        for pattern in oci_patterns:
            candidate = os.path.join(mc_deploy_base, pattern)
            if os.path.isdir(candidate) and os.path.exists(os.path.join(candidate, 'index.json')):
                oci_dir = candidate
                break

        if not oci_dir:
            bb.fatal(f"OCI image not found for {platform} ({mc}:{recipe})")
            bb.fatal(f"Looked in: {mc_deploy_base}")
            continue

        bb.plain(f"  Found {platform} OCI: {oci_dir}")

        # Read the source index.json
        with open(os.path.join(oci_dir, 'index.json'), 'r') as f:
            src_index = json.load(f)

        # Get the manifest entry (should be first/only one for single-arch)
        if not src_index.get('manifests'):
            bb.warn(f"No manifests found in {oci_dir}/index.json")
            continue

        src_manifest_entry = src_index['manifests'][0]
        manifest_digest = src_manifest_entry['digest']
        manifest_size = src_manifest_entry['size']

        # Copy all blobs from source to output
        src_blobs = os.path.join(oci_dir, 'blobs', 'sha256')
        dst_blobs = os.path.join(output_dir, 'blobs', 'sha256')

        if os.path.isdir(src_blobs):
            for blob in os.listdir(src_blobs):
                src_blob = os.path.join(src_blobs, blob)
                dst_blob = os.path.join(dst_blobs, blob)
                if not os.path.exists(dst_blob):
                    shutil.copy2(src_blob, dst_blob)
                    bb.note(f"    Copied blob: {blob[:12]}...")

        # Create manifest entry with platform info
        manifest_entry = {
            'mediaType': 'application/vnd.oci.image.manifest.v1+json',
            'digest': manifest_digest,
            'size': manifest_size,
            'platform': {
                'architecture': oci_platform,
                'os': 'linux'
            }
        }
        index_manifests.append(manifest_entry)
        bb.plain(f"    Added {oci_platform}/linux manifest: {manifest_digest[:19]}...")

    if not index_manifests:
        bb.fatal("No manifests collected - cannot create multi-arch index")

    # Create the OCI Image Index as a blob (not directly in index.json).
    # skopeo requires index.json to reference a single entry; the actual
    # multi-platform manifest list lives in blobs/sha256/ and index.json
    # points to it.
    image_index = {
        'schemaVersion': 2,
        'mediaType': 'application/vnd.oci.image.index.v1+json',
        'manifests': index_manifests
    }

    image_index_json = json.dumps(image_index, indent=2).encode('utf-8')
    image_index_digest = hashlib.sha256(image_index_json).hexdigest()
    image_index_size = len(image_index_json)

    # Write the image index as a blob
    blob_path = os.path.join(output_dir, 'blobs', 'sha256', image_index_digest)
    with open(blob_path, 'wb') as f:
        f.write(image_index_json)

    # Write index.json pointing to the image index blob
    top_index = {
        'schemaVersion': 2,
        'manifests': [
            {
                'mediaType': 'application/vnd.oci.image.index.v1+json',
                'digest': f'sha256:{image_index_digest}',
                'size': image_index_size
            }
        ]
    }

    index_path = os.path.join(output_dir, 'index.json')
    with open(index_path, 'w') as f:
        json.dump(top_index, f, indent=2)

    # Write oci-layout
    layout_path = os.path.join(output_dir, 'oci-layout')
    with open(layout_path, 'w') as f:
        json.dump({'imageLayoutVersion': '1.0.0'}, f)

    bb.plain("")
    bb.plain(f"Created multi-arch OCI Image Index:")
    bb.plain(f"  {output_dir}")
    bb.plain(f"  Platforms: {', '.join(d.getVarFlag('OCI_ARCH_TO_PLATFORM', p) or p for p in platforms)}")
    bb.plain("")
    bb.plain("To import into vdkr (will auto-select platform):")
    bb.plain(f"  vdkr vimport {output_dir} {recipe}:latest")
}

addtask do_create_multiarch_index before do_build

# Stamp includes platforms to rebuild when platforms change
do_create_multiarch_index[stamp-extra-info] = "${OCI_MULTIARCH_PLATFORMS}"

# Deploy the multi-arch OCI
python do_deploy() {
    import os
    import shutil

    output_dir = d.getVar('OCI_MULTIARCH_OUTPUT')
    deploy_dir = d.getVar('DEPLOY_DIR_IMAGE')

    # Already deployed in place (output_dir is in deploy_dir)
    # Just verify it exists
    if not os.path.exists(os.path.join(output_dir, 'index.json')):
        bb.fatal(f"Multi-arch OCI not found: {output_dir}")

    bb.plain(f"Multi-arch OCI available at: {output_dir}")
}

addtask do_deploy after do_create_multiarch_index before do_build

EXCLUDE_FROM_WORLD = "1"
