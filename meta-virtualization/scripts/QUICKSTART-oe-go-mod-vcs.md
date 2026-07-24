# Quickstart: Go Module VCS Build System for Yocto/BitBake

This guide covers how to create and maintain Go recipes using the `go-mod-vcs` system, which provides reproducible, offline Go builds by fetching dependencies directly from their git repositories.

## Overview

The `go-mod-vcs` system replaces vendor directories with a build-time module cache constructed from git repositories. This provides:

- **Reproducible builds** - Every module comes from a verified git commit
- **Offline builds** - After `do_fetch`, no network access is required
- **Auditable dependencies** - Every dependency is traceable to a specific git commit
- **Smaller recipes** - No need to maintain large vendor directories in source trees

### How It Works

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Your Recipe                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐ │
│  │ myapp_git.bb    │  │ go-mod-git.inc  │  │ go-mod-cache.inc    │ │
│  │ (your code)     │  │ (git fetches)   │  │ (module metadata)   │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────────┘ │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
   ┌─────────┐           ┌─────────────┐         ┌───────────────┐
   │do_fetch │           │do_create_   │         │  do_compile   │
   │         │──────────▶│module_cache │────────▶│               │
   │(git)    │           │(build cache)│         │(go build)     │
   └─────────┘           └─────────────┘         └───────────────┘
```

1. **do_fetch** - BitBake fetches all git repositories listed in `go-mod-git.inc`
2. **do_create_module_cache** - The `go-mod-vcs` class builds a Go module cache from git checkouts
3. **do_compile** - Go builds offline using the pre-populated module cache

---

## Converting an Existing Recipe

### Step 1: Add Discovery Configuration

Add these lines to your recipe (before `inherit go`):

```bitbake
# go-mod-discovery configuration
GO_MOD_DISCOVERY_BUILD_TARGET = "./cmd/..."      # Your build target
GO_MOD_DISCOVERY_GIT_REPO = "https://github.com/org/repo.git"
GO_MOD_DISCOVERY_GIT_REF = "${SRCREV}"

inherit go-mod-discovery
```

### Step 2: Include the Generated Files

Add includes after your `SRC_URI`:

```bitbake
SRC_URI = "git://github.com/org/repo;branch=main;protocol=https;destsuffix=${GO_SRCURI_DESTSUFFIX}"

include go-mod-git.inc
include go-mod-cache.inc
```

### Step 3: Create Placeholder Files

Create empty placeholder files (they'll be generated):

```bash
cd recipes-containers/myapp/
touch go-mod-git.inc go-mod-cache.inc
```

### Step 4: Run Discovery

```bash
bitbake myapp -c discover_and_generate
```

This will:
1. Build your project with network access to discover dependencies
2. Extract module metadata from the Go module cache
3. Generate `go-mod-git.inc` and `go-mod-cache.inc` files

### Step 5: Update do_compile()

Ensure your `do_compile()` doesn't set conflicting environment variables. The `go-mod-vcs.bbclass` automatically sets:

- `GOMODCACHE` - Points to the built module cache
- `GOPROXY=off` - Enforces offline build
- `GOSUMDB=off` - Disables checksum database
- `GOTOOLCHAIN=local` - Uses the native Go toolchain

A minimal `do_compile()`:

```bitbake
do_compile() {
    cd ${S}/src/import

    export GOPATH="${S}/src/import/.gopath:${STAGING_DIR_TARGET}/${prefix}/local/go"
    export CGO_ENABLED="1"

    ${GO} build -trimpath ./cmd/...
}
```

### Step 6: Build and Test

```bash
bitbake myapp
```

---

## Creating a New Recipe

### Minimal Recipe Template

```bitbake
SUMMARY = "My Go Application"
HOMEPAGE = "https://github.com/org/myapp"

SRCREV = "abc123def456..."
SRC_URI = "git://github.com/org/myapp;branch=main;protocol=https;destsuffix=${GO_SRCURI_DESTSUFFIX}"

include go-mod-git.inc
include go-mod-cache.inc

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://src/import/LICENSE;md5=..."

GO_IMPORT = "import"
PV = "v1.0.0+git"

# go-mod-discovery configuration
GO_MOD_DISCOVERY_BUILD_TARGET = "./cmd/..."
GO_MOD_DISCOVERY_GIT_REPO = "https://github.com/org/myapp.git"
GO_MOD_DISCOVERY_GIT_REF = "${SRCREV}"

inherit go goarch
inherit go-mod-discovery

do_compile() {
    cd ${S}/src/import

    export GOPATH="${S}/src/import/.gopath:${STAGING_DIR_TARGET}/${prefix}/local/go"
    export CGO_ENABLED="1"

    ${GO} build -trimpath -o ${B}/myapp ./cmd/myapp
}

do_install() {
    install -d ${D}${bindir}
    install -m 755 ${B}/myapp ${D}${bindir}/
}
```

### Generate Dependencies

```bash
# Create placeholder files
touch go-mod-git.inc go-mod-cache.inc

# Run discovery
bitbake myapp -c discover_and_generate

# Build
bitbake myapp
```

---

## Updating a Recipe to a New Version

### Quick Update (Same Repository)

1. **Update the SRCREV** in your recipe:
   ```bitbake
   SRCREV = "new_commit_hash_here"
   ```

2. **Re-run discovery**:
   ```bash
   bitbake myapp -c discover_and_generate
   ```

3. **Build**:
   ```bash
   bitbake myapp
   ```

### Full Workflow Example

```bash
# 1. Find the new commit/tag
git ls-remote https://github.com/org/myapp refs/tags/v2.0.0

# 2. Update SRCREV in recipe
# SRCREV = "abc123..."

# 3. Clean old discovery cache (optional, recommended for major updates)
bitbake myapp -c clean_discovery

# 4. Run discovery and generation
bitbake myapp -c discover_and_generate

# 5. Review generated files
git diff recipes-containers/myapp/go-mod-*.inc

# 6. Build and test
bitbake myapp

# 7. Commit changes
git add recipes-containers/myapp/
git commit -m "myapp: update to v2.0.0"
```

---

## Discovery Tasks Reference

| Task | Purpose | Network? |
|------|---------|----------|
| `discover_modules` | Build project and download modules from proxy | Yes |
| `extract_modules` | Extract metadata from cache to JSON | No |
| `generate_modules` | Generate .inc files from metadata | No |
| `discover_and_generate` | All three steps in sequence | Yes |
| `show_upgrade_commands` | Print command lines without running | No |
| `clean_discovery` | Remove the discovery cache | No |

### Step-by-Step vs All-in-One

**All-in-one** (recommended for most cases):
```bash
bitbake myapp -c discover_and_generate
```

**Step-by-step** (useful for debugging):
```bash
bitbake myapp -c discover_modules    # Download modules
bitbake myapp -c extract_modules     # Extract to JSON
bitbake myapp -c generate_modules    # Generate .inc files
```

---

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GO_MOD_DISCOVERY_BUILD_TARGET` | *(required)* | Go build target (e.g., `./cmd/...`) |
| `GO_MOD_DISCOVERY_GIT_REPO` | *(required for generate)* | Git repository URL |
| `GO_MOD_DISCOVERY_GIT_REF` | `${SRCREV}` | Git commit/tag |
| `GO_MOD_DISCOVERY_SRCDIR` | `${S}/src/import` | Directory containing go.mod |
| `GO_MOD_DISCOVERY_BUILD_TAGS` | `${TAGS}` | Go build tags |
| `GO_MOD_DISCOVERY_RECIPEDIR` | `${FILE_DIRNAME}` | Output directory for .inc files |

---

## Troubleshooting

### "module lookup disabled by GOPROXY=off"

This error during `do_compile` means a module is missing from the cache.

**Fix:**
```bash
# Re-run discovery to find missing modules
bitbake myapp -c discover_and_generate
bitbake myapp
```

### Discovery Cache Location

The discovery cache persists in `${TOPDIR}/go-mod-discovery/${PN}/${PV}/` and survives `bitbake -c cleanall`. To fully reset:

```bash
bitbake myapp -c clean_discovery
bitbake myapp -c discover_and_generate
```

### Viewing Generated Commands

To see what commands would be run without executing them:

```bash
bitbake myapp -c show_upgrade_commands
```

### Build Fails After SRCREV Update

If changing SRCREV causes sstate errors:

```bash
# Clean sstate for the recipe
bitbake myapp -c cleansstate

# Re-run discovery
bitbake myapp -c discover_and_generate

# Build
bitbake myapp
```

### Multiple Source Repositories

For recipes with multiple git sources, use named SRCREVs:

```bitbake
SRCREV_myapp = "abc123..."
SRCREV_plugins = "def456..."
SRCREV_FORMAT = "myapp_plugins"

SRC_URI = "\
    git://github.com/org/myapp;name=myapp;branch=main;protocol=https;destsuffix=${GO_SRCURI_DESTSUFFIX} \
    git://github.com/org/plugins;name=plugins;branch=main;protocol=https;destsuffix=${GO_SRCURI_DESTSUFFIX}/plugins \
"

GO_MOD_DISCOVERY_GIT_REF = "${SRCREV_myapp}"
```

---

## Example Recipes

### Simple Recipe (rootlesskit)

```bitbake
SRCREV_rootless = "8059d35092db167ec53cae95fb6aa37fc577060c"
SRCREV_FORMAT = "rootless"

SRC_URI = "git://github.com/rootless-containers/rootlesskit;name=rootless;branch=master;protocol=https;destsuffix=${GO_SRCURI_DESTSUFFIX}"

include go-mod-git.inc
include go-mod-cache.inc

GO_MOD_DISCOVERY_BUILD_TARGET = "./cmd/..."
GO_MOD_DISCOVERY_GIT_REPO = "https://github.com/rootless-containers/rootlesskit.git"
GO_MOD_DISCOVERY_GIT_REF = "${SRCREV_rootless}"

inherit go goarch go-mod-discovery
```

### Complex Recipe (k3s with build tags)

```bitbake
TAGS = "static_build netcgo osusergo providerless"

GO_MOD_DISCOVERY_BUILD_TARGET = "./cmd/server/main.go"
GO_MOD_DISCOVERY_GIT_REPO = "https://github.com/rancher/k3s.git"
GO_MOD_DISCOVERY_GIT_REF = "${SRCREV_k3s}"

inherit go goarch go-mod-discovery
```

---

## Files Generated

### go-mod-git.inc

Contains `SRC_URI` entries for each module's git repository:

```bitbake
SRC_URI += "git://github.com/spf13/cobra;protocol=https;nobranch=1;rev=e94f6d0...;name=git_41456771_1;destsuffix=vcs_cache/2d91d6bc..."
```

### go-mod-cache.inc

Contains module metadata and inherits the build class:

```bitbake
inherit go-mod-vcs

GO_MODULE_CACHE_DATA = '[{"module":"github.com/spf13/cobra","version":"v1.8.1","vcs_hash":"2d91d6bc...","timestamp":"2024-06-01T10:31:11Z","subdir":""},...]'
```

---

## Hybrid Mode: Mixing gomod:// and git:// Fetchers

For large projects like k3s with hundreds of modules, the VCS-only approach (all `git://`) can be slow due to the large number of git clones. **Hybrid mode** provides a faster alternative by using:

- `gomod://` - Fast proxy.golang.org downloads for most modules
- `git://` - VCS provenance for selected important modules (e.g., containerd, k8s.io)

### Benefits

| Mode | Fetch Speed | VCS Provenance | Use Case |
|------|-------------|----------------|----------|
| **VCS** (`git://` only) | Slower | Full | Security-critical, audit requirements |
| **Hybrid** (`gomod://` + `git://`) | Faster | Selective | Development, CI, most builds |

### Step 1: Build in VCS Mode First

Ensure your recipe works in VCS mode before converting:

```bash
bitbake myapp -c discover_and_generate
bitbake myapp
```

### Step 2: Run Recommendations

After a successful VCS build, analyze which modules to keep as git:// vs convert to gomod://:

```bash
bitbake myapp -c go_mod_recommend
```

This outputs size-based recommendations and suggests prefixes to keep as `git://`.

### Step 3: Generate Hybrid Files

Use the hybrid conversion script with suggested prefixes:

```bash
python3 ./meta-virtualization/scripts/oe-go-mod-fetcher-hybrid.py \
    --recipedir ./meta-virtualization/recipes-containers/myapp/ \
    --workdir ${WORKDIR} \
    --git "github.com/containerd,k8s.io,sigs.k8s.io"
```

This generates three new files:
- `go-mod-hybrid-gomod.inc` - SRC_URI entries for gomod:// fetcher (with inline checksums)
- `go-mod-hybrid-git.inc` - SRC_URI entries for git:// fetcher (VCS provenance)
- `go-mod-hybrid-cache.inc` - Module metadata for the git:// modules

### Step 4: Configure Recipe for Mode Switching

Update your recipe to allow switching between modes:

```bitbake
# GO_MOD_FETCH_MODE: "vcs" (all git://) or "hybrid" (gomod:// + git://)
GO_MOD_FETCH_MODE ?= "vcs"

# VCS mode: all modules via git://
include ${@ "go-mod-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}
include ${@ "go-mod-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "vcs" else ""}

# Hybrid mode: gomod:// for most, git:// for selected
include ${@ "go-mod-hybrid-gomod.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-git.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
include ${@ "go-mod-hybrid-cache.inc" if d.getVar("GO_MOD_FETCH_MODE") == "hybrid" else ""}
```

### Step 5: Switch Modes

Switch between modes in `local.conf`:

```bash
# Use hybrid mode (faster)
GO_MOD_FETCH_MODE = "hybrid"

# Or use VCS mode (full provenance)
GO_MOD_FETCH_MODE = "vcs"
```

Then rebuild:

```bash
bitbake myapp
```

### Hybrid Script Options

| Option | Description |
|--------|-------------|
| `--recipedir` | Recipe directory containing go-mod-git.inc and go-mod-cache.inc |
| `--workdir` | BitBake workdir for size calculations (optional) |
| `--git "prefixes"` | Comma-separated prefixes to keep as git:// (everything else becomes gomod://) |
| `--gomod "prefixes"` | Comma-separated prefixes to convert to gomod:// (everything else stays git://) |
| `--no-checksums` | Skip fetching SHA256 checksums (not recommended) |
| `--list` | List all modules with sizes |
| `--recommend` | Show size-based conversion recommendations |

### Example: k3s Hybrid Conversion

```bash
# 1. Ensure VCS mode works first
bitbake k3s

# 2. Get recommendations
bitbake k3s -c go_mod_recommend

# 3. Convert with recommended prefixes (keep containerd, k8s.io as git://)
python3 ./meta-virtualization/scripts/oe-go-mod-fetcher-hybrid.py \
    --recipedir ./meta-virtualization/recipes-containers/k3s/ \
    --git "github.com/containerd,k8s.io,sigs.k8s.io,github.com/rancher"

# 4. Enable hybrid mode
echo 'GO_MOD_FETCH_MODE = "hybrid"' >> conf/local.conf

# 5. Build in hybrid mode
bitbake k3s
```

### Troubleshooting Hybrid Builds

#### "Permission denied" during do_unpack

Go's module cache creates read-only files. The `go-mod-vcs.bbclass` includes automatic permission fixes, but if you hit this on an existing build:

```bash
chmod -R u+w ${WORKDIR}/sources/
bitbake myapp
```

#### BitBake parse errors with special characters

Module paths like `git.sr.ht/~sbinet/gg` contain characters (`~`) that can cause BitBake parse errors in variable flag names. The hybrid script uses inline checksums (`sha256sum=...` in the SRC_URI) to avoid this issue.

---

## Advanced: Manual Script Invocation

For cases where BitBake isn't available or you need more control:

```bash
# Direct generation from git (no BitBake needed)
python3 ./meta-virtualization/scripts/oe-go-mod-fetcher.py \
    --git-repo https://github.com/org/myapp.git \
    --git-ref abc123... \
    --recipedir ./meta-virtualization/recipes-containers/myapp/

# Using existing discovery cache
python3 ./meta-virtualization/scripts/oe-go-mod-fetcher.py \
    --discovered-modules ${TOPDIR}/go-mod-discovery/myapp/v1.0.0/modules.json \
    --git-repo https://github.com/org/myapp.git \
    --git-ref abc123... \
    --recipedir ./meta-virtualization/recipes-containers/myapp/
```

---

## Getting Help

- **Show available commands**: `bitbake myapp -c show_upgrade_commands`
- **Architecture details**: See `scripts/ARCHITECTURE.md`
- **Report issues**: Check the generated files and error messages from discovery

