#
# Copyright OpenEmbedded Contributors
#
# SPDX-License-Identifier: MIT
#

# go-mod-discovery.bbclass
#
# Provides tasks for Go module discovery and recipe generation.
#
# AVAILABLE TASKS:
#
#   bitbake <recipe> -c discover_modules
#       Build project and download modules from proxy.golang.org
#       This populates the discovery cache but does NOT extract or generate
#
#   bitbake <recipe> -c extract_modules
#       Extract module metadata from discovery cache to modules.json
#       Requires: discover_modules to have been run first
#
#   bitbake <recipe> -c generate_modules
#       Generate go-mod-git.inc and go-mod-cache.inc from modules.json
#       Requires: extract_modules to have been run first
#
#   bitbake <recipe> -c discover_and_generate
#       Run all three steps: discover -> extract -> generate
#       This is the "do everything" convenience task
#
#   bitbake <recipe> -c show_upgrade_commands
#       Show copy-pasteable command lines without running anything
#
#   bitbake <recipe> -c clean_discovery
#       Remove the persistent discovery cache
#
#   bitbake <recipe> -c update_license_hashes
#       Regenerate the bundled license-hashes.csv from COMMON_LICENSE_DIR
#       Run after OE-core upgrades to keep standalone CSV current
#
# CONFIGURATION:
#
# Required (must be set by recipe):
#
#   GO_MOD_DISCOVERY_BUILD_TARGET - Build target for go build
#                                   Example: "./cmd/server" or "./..."
#
# Optional (have sensible defaults):
#
#   GO_MOD_DISCOVERY_SRCDIR     - Directory containing go.mod
#                                 Default: "${S}/src/import" (standard Go recipe layout)
#
#   GO_MOD_DISCOVERY_BUILD_TAGS - Build tags for go build
#                                 Default: "${TAGS}" (uses recipe's TAGS variable if set)
#                                 Example: "netcgo osusergo static_build"
#
#   GO_MOD_DISCOVERY_LDFLAGS    - Linker flags for go build
#                                 Default: "-w -s"
#                                 Example: "-X main.version=${PV} -w -s"
#
#   GO_MOD_DISCOVERY_GOPATH     - GOPATH for discovery build
#                                 Default: "${S}/src/import/.gopath:${S}/src/import/vendor"
#
#   GO_MOD_DISCOVERY_OUTPUT     - Output binary path
#                                 Default: "${WORKDIR}/discovery-build-output"
#
#   GO_MOD_DISCOVERY_DIR        - Persistent cache location
#                                 Default: "${TOPDIR}/go-mod-discovery/${PN}/${PV}"
#
#   GO_MOD_DISCOVERY_MODULES_JSON - Output path for extracted module metadata
#                                   Default: "${GO_MOD_DISCOVERY_DIR}/modules.json"
#
#   GO_MOD_DISCOVERY_GIT_REPO     - Git repository URL for recipe generation
#                                   Example: "https://github.com/rancher/k3s.git"
#                                   Required for generate_modules task
#
#   GO_MOD_DISCOVERY_GIT_REF      - Git ref (commit/tag) for recipe generation
#                                   Default: "${SRCREV}" (uses recipe's SRCREV)
#
#   GO_MOD_DISCOVERY_RECIPEDIR    - Output directory for generated .inc files
#                                   Default: "${FILE_DIRNAME}" (recipe's directory)
#
#   GO_MOD_DISCOVERY_SKIP_LICENSES - Set to "1" to skip license scanning
#                                    Default: "" (scan enabled)
#
# WORKFLOW EXAMPLES:
#
# Full automatic (one command does everything):
#   bitbake myapp -c discover_and_generate
#
# Step by step (useful for debugging or rerunning individual steps):
#   bitbake myapp -c discover_modules    # Download modules
#   bitbake myapp -c extract_modules     # Extract metadata
#   bitbake myapp -c generate_modules    # Generate .inc files
#
# Skip BitBake, use scripts directly (see show_upgrade_commands):
#   bitbake myapp -c show_upgrade_commands
#
# PERSISTENT CACHE: The discovery cache is stored in ${TOPDIR}/go-mod-discovery/${PN}/${PV}/
# This ensures the cache survives `bitbake <recipe> -c cleanall`.
# To clean: bitbake <recipe> -c clean_discovery

# Required variable (must be set by recipe)
GO_MOD_DISCOVERY_BUILD_TARGET ?= ""

# Optional variables with sensible defaults for standard Go recipe layout
GO_MOD_DISCOVERY_SRCDIR ?= "${S}/src/import"
GO_MOD_DISCOVERY_BUILD_TAGS ?= "${TAGS}"
GO_MOD_DISCOVERY_LDFLAGS ?= "-w -s"
GO_MOD_DISCOVERY_GOPATH ?= "${S}/src/import/.gopath:${S}/src/import/vendor"
GO_MOD_DISCOVERY_OUTPUT ?= "${WORKDIR}/discovery-build-output"

# Persistent discovery cache location - survives cleanall
GO_MOD_DISCOVERY_DIR ?= "${TOPDIR}/go-mod-discovery/${PN}/${PV}"

# Output JSON file for discovered modules (used by oe-go-mod-fetcher.py --discovered-modules)
GO_MOD_DISCOVERY_MODULES_JSON ?= "${GO_MOD_DISCOVERY_DIR}/modules.json"

# Git repository URL for recipe generation (required for generate_modules)
# Example: "https://github.com/rancher/k3s.git"
GO_MOD_DISCOVERY_GIT_REPO ?= ""

# Git ref (commit/tag) for recipe generation - defaults to recipe's SRCREV
GO_MOD_DISCOVERY_GIT_REF ?= "${SRCREV}"

# Recipe directory for generated .inc files - defaults to recipe's directory
GO_MOD_DISCOVERY_RECIPEDIR ?= "${FILE_DIRNAME}"

# Skip commit verification during generation (use cached results only)
# Set to "1" to skip verification on retries after initial discovery
# Usage: GO_MOD_DISCOVERY_SKIP_VERIFY = "1" in local.conf or recipe
GO_MOD_DISCOVERY_SKIP_VERIFY ?= ""

# Skip license scanning during generation
# Set to "1" to bypass license scanning (default: scan licenses)
# Usage: GO_MOD_DISCOVERY_SKIP_LICENSES = "1" in local.conf or recipe
GO_MOD_DISCOVERY_SKIP_LICENSES ?= ""

# Modules to exclude from git:// generation (space-separated prefixes)
# Excluded modules must be fetched via gomod:// in the recipe's SRC_URI
# Usage: GO_MOD_VCS_EXCLUDE = "github.com/vtolstov/go-ioctl"
GO_MOD_VCS_EXCLUDE ?= ""

# Empty default for TAGS if not set by recipe (avoids undefined variable errors)
TAGS ?= ""

# =============================================================================
# TASK 1: do_discover_modules - Build and download modules
# =============================================================================
# This task builds the project with network access to discover and download
# all required Go modules from proxy.golang.org into a persistent cache.
#
# Usage: bitbake <recipe> -c discover_modules
#
do_discover_modules() {
    # Validate required variable
    if [ -z "${GO_MOD_DISCOVERY_BUILD_TARGET}" ]; then
        bbfatal "GO_MOD_DISCOVERY_BUILD_TARGET must be set (e.g., './cmd/server' or './...')"
    fi

    # Validate source directory exists and contains go.mod
    if [ ! -d "${GO_MOD_DISCOVERY_SRCDIR}" ]; then
        bbfatal "GO_MOD_DISCOVERY_SRCDIR does not exist: ${GO_MOD_DISCOVERY_SRCDIR}
Hint: Set GO_MOD_DISCOVERY_SRCDIR in your recipe if go.mod is not in \${S}/src/import"
    fi
    if [ ! -f "${GO_MOD_DISCOVERY_SRCDIR}/go.mod" ]; then
        bbfatal "go.mod not found in GO_MOD_DISCOVERY_SRCDIR: ${GO_MOD_DISCOVERY_SRCDIR}
Hint: Set GO_MOD_DISCOVERY_SRCDIR to the directory containing go.mod"
    fi

    # Use PERSISTENT cache location outside WORKDIR to survive cleanall
    DISCOVERY_CACHE="${GO_MOD_DISCOVERY_DIR}/cache"

    # Create required directories
    mkdir -p "${DISCOVERY_CACHE}"
    mkdir -p "${WORKDIR}/go-tmp"
    mkdir -p "$(dirname "${GO_MOD_DISCOVERY_OUTPUT}")"

    # Use discovery-cache instead of the normal GOMODCACHE
    export GOMODCACHE="${DISCOVERY_CACHE}"

    # Enable network access to proxy.golang.org
    export GOPROXY="https://proxy.golang.org,direct"
    export GOSUMDB="sum.golang.org"

    # Standard Go environment
    export GOPATH="${GO_MOD_DISCOVERY_GOPATH}:${STAGING_DIR_TARGET}/${prefix}/local/go"
    export CGO_ENABLED="1"
    export GOTOOLCHAIN="local"
    export GOTMPDIR="${WORKDIR}/go-tmp"

    # Disable excessive debug output
    unset GODEBUG

    # Build tags from recipe configuration
    TAGS="${GO_MOD_DISCOVERY_BUILD_TAGS}"

    cd "${GO_MOD_DISCOVERY_SRCDIR}"

    echo "======================================================================"
    echo "MODULE DISCOVERY: ${PN} ${PV}"
    echo "======================================================================"
    echo "GOMODCACHE:    ${GOMODCACHE}"
    echo "GOPROXY:       ${GOPROXY}"
    echo "Source dir:    ${GO_MOD_DISCOVERY_SRCDIR}"
    echo "Build target:  ${GO_MOD_DISCOVERY_BUILD_TARGET}"
    echo "Build tags:    ${TAGS:-<none>}"
    echo "LDFLAGS:       ${GO_MOD_DISCOVERY_LDFLAGS}"
    echo ""

    # Restore original go.sum from git if it was modified by do_create_module_cache
    # The build task rewrites go.sum with git-based checksums, but discovery needs
    # the original proxy-based checksums to download from proxy.golang.org
    if git -C "${GO_MOD_DISCOVERY_SRCDIR}" diff --quiet go.sum 2>/dev/null; then
        echo "go.sum is clean"
    else
        echo "Restoring original go.sum from git (was modified by previous build)..."
        git -C "${GO_MOD_DISCOVERY_SRCDIR}" checkout go.sum
    fi

    # Use native go binary
    GO_NATIVE="${STAGING_DIR_NATIVE}${bindir_native}/go"

    echo ""
    echo "Running: go build (to discover all modules)..."

    BUILD_CMD="${GO_NATIVE} build -v -trimpath"
    if [ -n "${TAGS}" ]; then
        BUILD_CMD="${BUILD_CMD} -tags \"${TAGS}\""
    fi
    BUILD_CMD="${BUILD_CMD} -ldflags \"${GO_MOD_DISCOVERY_LDFLAGS}\""

    # When building multiple packages (./... or multiple targets), go build
    # requires the output to be a directory. Create the directory and use it.
    mkdir -p "${GO_MOD_DISCOVERY_OUTPUT}"
    BUILD_CMD="${BUILD_CMD} -o \"${GO_MOD_DISCOVERY_OUTPUT}/\" ${GO_MOD_DISCOVERY_BUILD_TARGET}"

    echo "Executing: ${BUILD_CMD}"
    eval ${BUILD_CMD}

    echo ""
    echo "Fetching ALL modules referenced in go.sum..."
    awk '{gsub(/\/go\.mod$/, "", $2); print $1 "@" $2}' go.sum | sort -u | while read modver; do
        ${GO_NATIVE} mod download "$modver" 2>/dev/null || true
    done

    echo ""
    echo "Downloading complete module graph (including transitive deps)..."
    ${GO_NATIVE} mod download all 2>&1 || echo "Warning: some modules may have failed to download"

    echo ""
    echo "Ensuring .info files for all cached modules..."
    find "${GOMODCACHE}/cache/download" -name "*.zip" 2>/dev/null | while read zipfile; do
        version=$(basename "$zipfile" .zip)
        moddir=$(dirname "$zipfile")
        infofile="${moddir}/${version}.info"
        if [ ! -f "$infofile" ]; then
            modpath=$(echo "$moddir" | sed "s|${GOMODCACHE}/cache/download/||" | sed 's|/@v$||')
            echo "  Fetching .info for: ${modpath}@${version}"
            ${GO_NATIVE} mod download "${modpath}@${version}" 2>/dev/null || true
        fi
    done

    echo ""
    echo "Downloading dependencies of replaced modules..."
    awk '/^replace \($/,/^\)$/ {if ($0 !~ /^replace|^\)/) print}' go.mod | \
    grep "=>" | while read line; do
        new_module=$(echo "$line" | awk '{print $(NF-1)}')
        new_version=$(echo "$line" | awk '{print $NF}')
        if [ -n "$new_module" ] && [ -n "$new_version" ] && [ "$new_version" != "=>" ]; then
            echo "  Replace target: ${new_module}@${new_version}"
            ${GO_NATIVE} mod download "${new_module}@${new_version}" 2>/dev/null || true
        fi
    done

    MODULE_COUNT=$(find "${GOMODCACHE}/cache/download" -name "*.info" 2>/dev/null | wc -l)

    echo ""
    echo "======================================================================"
    echo "DISCOVERY COMPLETE"
    echo "======================================================================"
    echo "Modules discovered: ${MODULE_COUNT}"
    echo "Cache location:     ${GOMODCACHE}"
    echo ""
    echo "Next steps:"
    echo "  bitbake ${PN} -c extract_modules   # Extract metadata to JSON"
    echo "  bitbake ${PN} -c generate_modules  # Generate .inc files"
    echo ""
    echo "Or run all at once:"
    echo "  bitbake ${PN} -c discover_and_generate"
    echo ""
}

# Run after do_unpack but NOT after do_patch - patches often fail during uprevs
# and are rarely needed for discovery (they typically fix runtime behavior, not dependencies)
addtask discover_modules after do_unpack
do_discover_modules[depends] = "${PN}:do_prepare_recipe_sysroot"
do_discover_modules[network] = "1"
do_discover_modules[nostamp] = "1"
do_discover_modules[vardeps] += "GO_MOD_DISCOVERY_DIR GO_MOD_DISCOVERY_SRCDIR \
    GO_MOD_DISCOVERY_BUILD_TARGET GO_MOD_DISCOVERY_BUILD_TAGS \
    GO_MOD_DISCOVERY_LDFLAGS GO_MOD_DISCOVERY_GOPATH GO_MOD_DISCOVERY_OUTPUT"

# =============================================================================
# TASK 2: do_extract_modules - Extract metadata from cache
# =============================================================================
# This task extracts module metadata from the discovery cache into a JSON file.
# The JSON file can then be used with oe-go-mod-fetcher.py --discovered-modules.
#
# Usage: bitbake <recipe> -c extract_modules
#
do_extract_modules() {
    DISCOVERY_CACHE="${GO_MOD_DISCOVERY_DIR}/cache"

    if [ ! -d "${DISCOVERY_CACHE}/cache/download" ]; then
        bbfatal "Discovery cache not found: ${DISCOVERY_CACHE}
Run 'bitbake ${PN} -c discover_modules' first to populate the cache."
    fi

    echo "======================================================================"
    echo "EXTRACTING MODULE METADATA: ${PN} ${PV}"
    echo "======================================================================"
    echo "Cache:  ${DISCOVERY_CACHE}"
    echo "Output: ${GO_MOD_DISCOVERY_MODULES_JSON}"
    echo ""

    # Find the extraction script
    EXTRACT_SCRIPT=""
    for layer in ${BBLAYERS}; do
        if [ -f "${layer}/scripts/extract-discovered-modules.py" ]; then
            EXTRACT_SCRIPT="${layer}/scripts/extract-discovered-modules.py"
            break
        fi
    done

    if [ -z "${EXTRACT_SCRIPT}" ]; then
        bbfatal "Could not find extract-discovered-modules.py in any layer"
    fi

    python3 "${EXTRACT_SCRIPT}" \
        --gomodcache "${DISCOVERY_CACHE}" \
        --output "${GO_MOD_DISCOVERY_MODULES_JSON}"

    if [ $? -eq 0 ]; then
        MODULE_COUNT=$(python3 -c "import json; print(len(json.load(open('${GO_MOD_DISCOVERY_MODULES_JSON}'))['modules']))" 2>/dev/null || echo "?")
        echo ""
        echo "======================================================================"
        echo "EXTRACTION COMPLETE"
        echo "======================================================================"
        echo "Modules extracted: ${MODULE_COUNT}"
        echo "Output file:       ${GO_MOD_DISCOVERY_MODULES_JSON}"
        echo ""
        echo "Next step:"
        echo "  bitbake ${PN} -c generate_modules"
        echo ""
    else
        bbfatal "Module extraction failed"
    fi
}

addtask extract_modules
do_extract_modules[nostamp] = "1"
do_extract_modules[vardeps] += "GO_MOD_DISCOVERY_DIR GO_MOD_DISCOVERY_MODULES_JSON"

# =============================================================================
# TASK 3: do_generate_modules - Generate .inc files
# =============================================================================
# This task generates go-mod-git.inc and go-mod-cache.inc from the extracted
# modules.json file.
#
# Usage: bitbake <recipe> -c generate_modules
#
do_generate_modules() {
    if [ ! -f "${GO_MOD_DISCOVERY_MODULES_JSON}" ]; then
        bbfatal "Modules JSON not found: ${GO_MOD_DISCOVERY_MODULES_JSON}
Run 'bitbake ${PN} -c extract_modules' first to create the modules file."
    fi

    if [ -z "${GO_MOD_DISCOVERY_GIT_REPO}" ]; then
        bbfatal "GO_MOD_DISCOVERY_GIT_REPO must be set for recipe generation.
Add to your recipe: GO_MOD_DISCOVERY_GIT_REPO = \"https://github.com/...\"
Or run 'bitbake ${PN} -c show_upgrade_commands' to see manual options."
    fi

    # CRITICAL: Change to source directory so oe-go-mod-fetcher.py can find go.mod/go.sum
    cd "${GO_MOD_DISCOVERY_SRCDIR}"

    echo "======================================================================"
    echo "GENERATING RECIPE FILES: ${PN} ${PV}"
    echo "======================================================================"
    echo "Source dir:   ${GO_MOD_DISCOVERY_SRCDIR}"
    echo "Modules JSON: ${GO_MOD_DISCOVERY_MODULES_JSON}"
    echo "Git repo:     ${GO_MOD_DISCOVERY_GIT_REPO}"
    echo "Git ref:      ${GO_MOD_DISCOVERY_GIT_REF}"
    echo "Recipe dir:   ${GO_MOD_DISCOVERY_RECIPEDIR}"
    echo ""

    # Find the fetcher script
    FETCHER_SCRIPT=""
    for layer in ${BBLAYERS}; do
        if [ -f "${layer}/scripts/oe-go-mod-fetcher.py" ]; then
            FETCHER_SCRIPT="${layer}/scripts/oe-go-mod-fetcher.py"
            break
        fi
    done

    if [ -z "${FETCHER_SCRIPT}" ]; then
        bbfatal "Could not find oe-go-mod-fetcher.py in any layer"
    fi

    # Build fetcher command with optional flags
    SKIP_VERIFY_FLAG=""
    if [ "${GO_MOD_DISCOVERY_SKIP_VERIFY}" = "1" ]; then
        echo "NOTE: Skipping commit verification (GO_MOD_DISCOVERY_SKIP_VERIFY=1)"
        SKIP_VERIFY_FLAG="--skip-verify"
    fi

    EXCLUDE_FLAGS=""
    for mod in ${GO_MOD_VCS_EXCLUDE}; do
        EXCLUDE_FLAGS="${EXCLUDE_FLAGS} --exclude-module ${mod}"
    done

    LICENSE_FLAGS=""
    if [ "${GO_MOD_DISCOVERY_SKIP_LICENSES}" != "1" ]; then
        LICENSE_FLAGS="--scan-licenses --common-license-dir ${COMMON_LICENSE_DIR} --discovery-cache ${GO_MOD_DISCOVERY_DIR}/cache"
    fi

    python3 "${FETCHER_SCRIPT}" \
        --discovered-modules "${GO_MOD_DISCOVERY_MODULES_JSON}" \
        --git-repo "${GO_MOD_DISCOVERY_GIT_REPO}" \
        --git-ref "${GO_MOD_DISCOVERY_GIT_REF}" \
        --recipedir "${GO_MOD_DISCOVERY_RECIPEDIR}" \
        ${SKIP_VERIFY_FLAG} \
        ${EXCLUDE_FLAGS} \
        ${LICENSE_FLAGS}

    if [ $? -eq 0 ]; then
        echo ""
        echo "======================================================================"
        echo "GENERATION COMPLETE"
        echo "======================================================================"
        echo "Files generated in: ${GO_MOD_DISCOVERY_RECIPEDIR}"
        echo "  - go-mod-git.inc"
        echo "  - go-mod-cache.inc"
        echo "  - go-mod-licenses.inc (if license scanning enabled)"
        echo ""
        echo "You can now build the recipe:"
        echo "  bitbake ${PN}"
        echo ""
    else
        bbfatal "Recipe generation failed"
    fi
}

addtask generate_modules
do_generate_modules[nostamp] = "1"
do_generate_modules[vardeps] += "GO_MOD_DISCOVERY_MODULES_JSON GO_MOD_DISCOVERY_GIT_REPO \
    GO_MOD_DISCOVERY_GIT_REF GO_MOD_DISCOVERY_RECIPEDIR GO_MOD_DISCOVERY_SKIP_LICENSES"
do_generate_modules[postfuncs] = "do_show_hybrid_recommendation"

# Show hybrid conversion recommendations after VCS generation
python do_show_hybrid_recommendation() {
    """
    Show recommendations for converting to hybrid gomod:// + git:// mode.
    Runs automatically after generate_modules completes.
    """
    import subprocess
    from pathlib import Path

    recipedir = d.getVar('GO_MOD_DISCOVERY_RECIPEDIR')
    git_inc = Path(recipedir) / 'go-mod-git.inc'

    if not git_inc.exists():
        return

    # Find the hybrid script
    layerdir = None
    for layer in d.getVar('BBLAYERS').split():
        if 'meta-virtualization' in layer:
            layerdir = layer
            break

    if not layerdir:
        return

    scriptpath = Path(layerdir) / "scripts" / "oe-go-mod-fetcher-hybrid.py"
    if not scriptpath.exists():
        return

    bb.plain("")
    bb.plain("=" * 70)
    bb.plain("HYBRID MODE RECOMMENDATION")
    bb.plain("=" * 70)

    cmd = ['python3', str(scriptpath), '--recipedir', recipedir, '--recommend']

    # Try to find module sizes from discovery cache or vcs_cache
    discovery_dir = d.getVar('GO_MOD_DISCOVERY_DIR')
    workdir = d.getVar('WORKDIR')

    # Check discovery cache first (has .zip files with accurate sizes)
    if discovery_dir:
        discovery_cache = Path(discovery_dir) / 'cache' / 'cache' / 'download'
        if discovery_cache.exists():
            cmd.extend(['--discovery-cache', str(discovery_cache)])

    # Also check vcs_cache if it exists (from a previous build)
    if workdir:
        vcs_cache = Path(workdir) / 'sources' / 'vcs_cache'
        if vcs_cache.exists():
            cmd.extend(['--workdir', workdir])

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if result.stdout:
            for line in result.stdout.splitlines():
                bb.plain(line)
            bb.plain("")
            bb.plain("")
    except Exception as e:
        bb.note(f"Could not run hybrid recommendation: {e}")
}

# =============================================================================
# TASK 4: do_discover_and_generate - All-in-one convenience task
# =============================================================================
# This task runs discover_modules, extract_modules, and generate_modules
# in sequence. It's the "do everything" option.
#
# Usage: bitbake <recipe> -c discover_and_generate
#
do_discover_and_generate() {
    echo "======================================================================"
    echo "FULL DISCOVERY AND GENERATION: ${PN} ${PV}"
    echo "======================================================================"
    echo ""
    echo "This task will run:"
    echo "  1. discover_modules  - Build and download modules"
    echo "  2. extract_modules   - Extract metadata to JSON"
    echo "  3. generate_modules  - Generate .inc files"
    echo ""
}

# Chain the tasks together using task dependencies
python do_discover_and_generate_setdeps() {
    # This runs discover -> extract -> generate in sequence
    pass
}

# Run after do_unpack but NOT after do_patch - patches often fail during uprevs
addtask discover_and_generate after do_unpack
do_discover_and_generate[depends] = "${PN}:do_prepare_recipe_sysroot"
do_discover_and_generate[network] = "1"
do_discover_and_generate[nostamp] = "1"
do_discover_and_generate[postfuncs] = "do_discover_modules do_extract_modules do_generate_modules do_show_hybrid_recommendation"

# =============================================================================
# TASK: do_clean_discovery - Clean the persistent cache
# =============================================================================
do_clean_discovery() {
    if [ -d "${GO_MOD_DISCOVERY_DIR}" ]; then
        echo "Removing discovery cache: ${GO_MOD_DISCOVERY_DIR}"
        rm -rf "${GO_MOD_DISCOVERY_DIR}"
        echo "Discovery cache removed."
    else
        echo "Discovery cache not found: ${GO_MOD_DISCOVERY_DIR}"
    fi
}

addtask clean_discovery
do_clean_discovery[nostamp] = "1"
do_clean_discovery[vardeps] += "GO_MOD_DISCOVERY_DIR"

# =============================================================================
# TASK: do_show_upgrade_commands - Show command lines without running
# =============================================================================
python do_show_upgrade_commands() {
    import os

    pn = d.getVar('PN')
    pv = d.getVar('PV')
    git_repo = d.getVar('GO_MOD_DISCOVERY_GIT_REPO') or '<GIT_REPO_URL>'
    git_ref = d.getVar('GO_MOD_DISCOVERY_GIT_REF') or d.getVar('SRCREV') or '<GIT_REF>'
    recipedir = d.getVar('GO_MOD_DISCOVERY_RECIPEDIR') or d.getVar('FILE_DIRNAME')
    discovery_dir = d.getVar('GO_MOD_DISCOVERY_DIR')
    modules_json = d.getVar('GO_MOD_DISCOVERY_MODULES_JSON')

    # Find script locations
    fetcher_script = None
    extract_script = None
    for layer in d.getVar('BBLAYERS').split():
        candidate = os.path.join(layer, 'scripts', 'oe-go-mod-fetcher.py')
        if os.path.exists(candidate):
            fetcher_script = candidate
        candidate = os.path.join(layer, 'scripts', 'extract-discovered-modules.py')
        if os.path.exists(candidate):
            extract_script = candidate

    fetcher_script = fetcher_script or './meta-virtualization/scripts/oe-go-mod-fetcher.py'
    extract_script = extract_script or './meta-virtualization/scripts/extract-discovered-modules.py'

    bb.plain("")
    bb.plain("=" * 70)
    bb.plain(f"UPGRADE COMMANDS FOR: {pn} {pv}")
    bb.plain("=" * 70)
    bb.plain("")
    bb.plain("Option 1: Generate from git repository (no BitBake required)")
    bb.plain("-" * 70)
    bb.plain("")
    bb.plain("Run from your build directory:")
    bb.plain("")
    bb.plain(f"  {fetcher_script} \\")
    bb.plain(f"    --git-repo {git_repo} \\")
    bb.plain(f"    --git-ref {git_ref} \\")
    bb.plain(f"    --recipedir {recipedir}")
    bb.plain("")
    bb.plain("")
    bb.plain("Option 2: BitBake discovery (step by step)")
    bb.plain("-" * 70)
    bb.plain("")
    bb.plain(f"  bitbake {pn} -c discover_modules    # Download modules (needs network)")
    bb.plain(f"  bitbake {pn} -c extract_modules     # Extract metadata to JSON")
    bb.plain(f"  bitbake {pn} -c generate_modules    # Generate .inc files")
    bb.plain("")
    bb.plain("")
    bb.plain("Option 3: BitBake discovery (all-in-one)")
    bb.plain("-" * 70)
    bb.plain("")
    bb.plain(f"  bitbake {pn} -c discover_and_generate")
    bb.plain("")
    bb.plain("")
    bb.plain("Option 4: Use existing discovery cache")
    bb.plain("-" * 70)
    bb.plain("")
    bb.plain(f"Discovery cache: {discovery_dir}")
    bb.plain("")
    bb.plain("Extract modules from cache:")
    bb.plain("")
    bb.plain(f"  {extract_script} \\")
    bb.plain(f"    --gomodcache {discovery_dir}/cache \\")
    bb.plain(f"    --output {modules_json}")
    bb.plain("")
    bb.plain("Then generate .inc files:")
    bb.plain("")
    bb.plain(f"  {fetcher_script} \\")
    bb.plain(f"    --discovered-modules {modules_json} \\")
    bb.plain(f"    --git-repo {git_repo} \\")
    bb.plain(f"    --git-ref {git_ref} \\")
    bb.plain(f"    --recipedir {recipedir}")
    bb.plain("")
    bb.plain("Add --scan-licenses to also generate go-mod-licenses.inc:")
    bb.plain("")
    bb.plain(f"  {fetcher_script} \\")
    bb.plain(f"    --discovered-modules {modules_json} \\")
    bb.plain(f"    --git-repo {git_repo} \\")
    bb.plain(f"    --git-ref {git_ref} \\")
    bb.plain(f"    --recipedir {recipedir} \\")
    bb.plain(f"    --scan-licenses --discovery-cache {discovery_dir}/cache")
    bb.plain("")
    bb.plain("")
    bb.plain("Generated files:")
    bb.plain("-" * 70)
    bb.plain("")
    bb.plain("  go-mod-git.inc      - SRC_URI entries for fetching module git repos")
    bb.plain("  go-mod-cache.inc    - Module path mappings for cache creation")
    bb.plain("  go-mod-licenses.inc - LICENSE and LIC_FILES_CHKSUM for dependencies")
    bb.plain("")
    bb.plain("=" * 70)
    bb.plain("")
}

addtask show_upgrade_commands
do_show_upgrade_commands[nostamp] = "1"
do_show_upgrade_commands[vardeps] += "GO_MOD_DISCOVERY_GIT_REPO GO_MOD_DISCOVERY_GIT_REF \
    GO_MOD_DISCOVERY_RECIPEDIR GO_MOD_DISCOVERY_DIR GO_MOD_DISCOVERY_MODULES_JSON"

# =============================================================================
# TASK: do_update_license_hashes - Regenerate bundled license hash CSV
# =============================================================================
# Regenerates scripts/data/license-hashes.csv from ${COMMON_LICENSE_DIR}.
# Run after OE-core upgrades to keep the bundled CSV current for standalone users.
#
# Usage: bitbake <any-go-recipe> -c update_license_hashes
#
python do_update_license_hashes() {
    import subprocess
    from pathlib import Path

    common_license_dir = d.getVar('COMMON_LICENSE_DIR')
    if not common_license_dir or not os.path.isdir(common_license_dir):
        bb.fatal(f"COMMON_LICENSE_DIR not found: {common_license_dir}")

    # Find the generator script and output path
    layerdir = None
    for layer in d.getVar('BBLAYERS').split():
        candidate = os.path.join(layer, 'scripts', 'generate-license-hashes.py')
        if os.path.exists(candidate):
            layerdir = layer
            break

    if not layerdir:
        bb.fatal("Could not find generate-license-hashes.py in any layer")

    script = os.path.join(layerdir, 'scripts', 'generate-license-hashes.py')
    output = os.path.join(layerdir, 'scripts', 'data', 'license-hashes.csv')

    bb.plain(f"Regenerating {output} from {common_license_dir}")

    result = subprocess.run(
        ['python3', script, common_license_dir],
        capture_output=True, text=True, timeout=60
    )

    if result.returncode != 0:
        bb.fatal(f"generate-license-hashes.py failed: {result.stderr}")

    os.makedirs(os.path.dirname(output), exist_ok=True)
    with open(output, 'w') as f:
        f.write(result.stdout)

    lines = [l for l in result.stdout.splitlines() if l and not l.startswith('#')]
    bb.plain(f"Generated {len(lines)} license hash entries in {output}")
}

addtask update_license_hashes
do_update_license_hashes[nostamp] = "1"
