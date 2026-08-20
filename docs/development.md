# Developer Guide: `sagelite`

This document details the build system, architecture, recipe configuration, verification testing, release process, and future roadmap for `sagelite`.

---

## 1. Architecture Overview

`sagelite` packages standard pre-compiled Conda-Forge packages into a standalone, self-contained native Linux directory.

```text
[recipes/environment.<arch>.yml]
               │
               ▼  (micromamba create)
[$PREFIX (Staged Environment)]
               │
               ▼  (scripts/build.sh: Payload Optimization)
  1. Remove static libraries (*.a, *.la) except compiler internals
  2. Remove documentation, manual pages, and test suites
  3. Strip debug symbols from binaries and .so files
  4. Inject scripts/entrypoint.sh -> $PREFIX/sage
               │
               ▼  (conda-pack --compress-level 19 --ignore-missing-files)
[artifacts/sagemath-portable-<arch>.tar.zst]
```

### Core Components
1. **Upstream Source (`conda-forge`):** Provides binaries compiled against a `glibc 2.28` baseline sysroot.
2. **Solver & Staging (`micromamba`):** Resolves dependency graphs and unpacks packages in under a minute.
3. **Payload Optimization (`scripts/build.sh`):** Reduces total uncompressed footprint from ~8 GB to ~4.2 GB while preserving compiler static runtimes (`libgcc.a`, `libstdc++.a`).
4. **Fixed-Target Packaging (`conda-pack`):** Records prefix placeholders and compresses the tree with Zstandard level 19 into a ~1.3 GB archive.
5. **Entrypoint Wrapper (`scripts/entrypoint.sh`):** Resolves directory location, runs `conda-unpack` once upon initial launch at target destination, isolates environment (`unset PYTHONPATH`), and sources toolchain activation scripts.

---

## 2. Build Prerequisites

* **Operating System:** Linux (`x86_64` or `aarch64`)
* **Required Tools:** `curl`, `tar`, `bzip2`, `zstd`, `strip`
* **Internet Access:** Needed only during build to download packages from Conda-Forge.

> Note: `micromamba` is automatically downloaded into `.cache/bin/` by `scripts/build.sh` if not found in `$PATH`.

---

## 3. Local Build Workflow

### 3.1. Standard Build (Auto-Detect Architecture)

```bash
# Auto-detects architecture (x86_64 / aarch64) and builds artifacts/sagemath-portable-<arch>.tar.zst
./scripts/build.sh
```

### 3.2. Custom Recipe or Output Path

```bash
./scripts/build.sh recipes/environment.x86_64.yml artifacts/custom-sage-x86_64.tar.zst
```

---

## 4. Verification & Testing Workflow

### 4.1. Automated 5-Tier Verification Suite

`scripts/test.sh` runs five sequential validation tiers:

```bash
# 1. Extract archive directly to target test directory
mkdir -p /tmp/test-sagelite
tar --zstd -xf artifacts/sagemath-portable-x86_64.tar.zst -C /tmp/test-sagelite

# 2. Run verification suite (~30 seconds)
./scripts/test.sh /tmp/test-sagelite/sage
```

### 4.2. Test Tiers Summary

| Tier | Test Scope | Verification Method |
| :--- | :--- | :--- |
| **1. CAS Backends** | GAP, Singular, PARI/GP | Evaluates basic algebra and group theory assertions |
| **2. Official Doctests** | `sage.doctest` subsystem | Executes 1,300+ official tests on core combinatorics & algebra modules |
| **3. Cython JIT** | Embedded compiler toolchain | Compiles and runs a dynamic C extension via `cython_lambda` |
| **4. Pip Extensibility** | Package management | Validates isolated `pip` binary |
| **5. JupyterLab** | Interactive notebook server | Verifies headless server startup |

To run the extended full doctest suite across all Sage modules:

```bash
./scripts/test.sh /tmp/test-sagelite/sage full
```

---

## 5. Recipe Management Guidelines

Recipes are defined in `recipes/`:
* `recipes/environment.x86_64.yml` (Intel/AMD 64-bit)
* `recipes/environment.aarch64.yml` (ARM64)

### Rules for Updating Recipes
* **Channels:** Always lock channels to `conda-forge` and `nodefaults`.
* **Sage Version:** Use `sage = 10.*` wildcard to automatically track the latest stable 10.x release.
* **Python Version:** Pin to `python = 3.12.*`.
* **Compilers:** Include `gcc_<arch>`, `gxx_<arch>`, `gfortran_<arch>`, and `sysroot_<arch>`.
* **Packaging:** Include `conda-pack` and `zstandard`.

---

## 6. Critical Technical Invariants

1. **Preserve Compiler Static Runtimes:** When stripping static libraries in `scripts/build.sh`, never delete files under `lib/gcc/*` or `sysroot/*`. GCC requires internal static archives (`libgcc.a`, `libstdc++.a`) when compiling Cython extensions at runtime.
2. **Conda-Pack Missing Files Flag:** Always pass `--ignore-missing-files` to `conda-pack` because non-essential files are stripped prior to packing.
3. **Cython Globals in Non-Interactive Mode:** In CLI evaluation scripts (`sage -c "..."`), initialize user-space globals via `set_globals(globals())` before importing dynamically compiled Cython modules.
4. **Environment Isolation & Toolchain Activation:** The `./sage` wrapper must enforce `unset PYTHONPATH`, `PYTHONNOUSERSITE=1`, set `PYTHONHOME="$DIR"`, and source `$DIR/etc/conda/activate.d/*.sh` to prevent host pollution and correctly inject compiler sysroot flags.

---

## 7. CI/CD Matrix Pipeline

The GitHub Actions workflow (`.github/workflows/build.yml`) builds and tests on native runners:
* `x86_64` on `ubuntu-latest`
* `aarch64` on `ubuntu-24.04-arm`
* Caches `~/.micromamba/pkgs` keyed by recipe hash.
* Tests archive extraction to target path and executes `scripts/test.sh` on every build.

---

## 8. Release Tagging & Publishing Process

Release builds and GitHub Releases are driven entirely by Git tags or manual dispatch.

### 8.1. Publishing a Release via Git Tag

To release a specific version of SageMath (e.g. `10.9`, `10.10`):

```bash
# 1. Create an annotated tag matching SageMath's version
git tag -a v10.9 -m "Release SageMath v10.9"

# 2. Push the tag to GitHub
git push origin v10.9
```

#### What Happens Automatically:
1. GitHub Actions detects the tag push (`v10.9`).
2. The workflow parses `SAGELITE_VERSION=10.9` and instructs `micromamba` to build that exact version.
3. Both `x86_64` and `aarch64` runners compile, strip, package, and execute the 5-tier test suite.
4. If tests pass, GitHub Actions creates a GitHub Release titled **`SageMath v10.9`** and attaches:
   * `sagemath-portable-x86_64.tar.zst`
   * `sagemath-portable-x86_64.tar.zst.sha256`
   * `sagemath-portable-aarch64.tar.zst`
   * `sagemath-portable-aarch64.tar.zst.sha256`
   * `scripts/install.sh`

### 8.2. Tagging Multiple Releases on the Same Commit

Because Git tags are lightweight pointers, you can tag the same commit for different target versions:

```bash
git tag -a v10.8 -m "Release SageMath v10.8"
git push origin v10.8
```

Each pushed tag triggers its own independent GitHub Actions release workflow.

### 8.3. Manual Build Trigger via GitHub UI (`workflow_dispatch`)

You can also trigger builds and releases without tagging:
1. Navigate to the **Actions** tab in your GitHub repository.
2. Select **Build and Release sagelite**.
3. Click **Run workflow**:
   * Specify `version` (e.g. `10.9`, `10.10`, or `latest`).
   * Check **Publish as GitHub Release** if you want to publish directly to GitHub Releases.

---

## 9. Future Roadmap & Technical TODOs

### 1. Automated Requirements Replay on Upgrades (Phase 2 Lifecycle)
* **Goal:** Allow users to retain custom `pip install`ed packages when upgrading between minor SageMath releases without causing ABI conflicts with core libraries.
* **Tasks:**
  - [ ] **Build-Time Manifest Generation:** During `scripts/build.sh`, save the baseline bundled package names into `$PREFIX/lib/sagelite_manifest.txt` via `pip list --format=freeze | cut -d= -f1 | sort -u`.
  - [ ] **Pre-Flight Diffing in `install.sh`:** Before replacing `~/.local/share/sagelite`, diff the active environment's package list against `sagelite_manifest.txt` to capture only user-added packages into `~/.sage/custom_requirements.txt`.
  - [ ] **Post-Flight Replay:** Execute `$NEW_DIR/bin/python -m pip install -r ~/.sage/custom_requirements.txt` with non-fatal error handling so upgrade success is never blocked by external package build errors.

### 2. Desktop & GUI Menu Integration
* **Goal:** Enable users to launch SageMath interactive shell and JupyterLab directly from their desktop environment application menus (GNOME, KDE, XFCE).
* **Tasks:**
  - [ ] Add `./sage --install-desktop` subcommand.
  - [ ] Generate an XDG `.desktop` file at `~/.local/share/applications/sagelite.desktop` and `~/.local/share/applications/sagelite-jupyter.desktop`.
  - [ ] Install bundled SageMath SVG icon to `~/.local/share/icons/hicolor/scalable/apps/sagelite.svg`.

### 3. Automated Upstream Version Watcher (CI Cron)
* **Goal:** Automatically detect when new stable SageMath releases are published to Conda-Forge.
* **Tasks:**
  - [ ] Implement a scheduled GitHub Actions cron job (`.github/workflows/check-upstream.yml`) running weekly.
  - [ ] Query Conda-Forge channel API for the highest stable `sage` version tag.
  - [ ] If a newer version is discovered, automatically open a tracking issue or trigger a draft release build.

### 4. Offline / Air-Gapped Deployment Bundle
* **Goal:** Simplify installation on air-gapped compute clusters and offline machines without internet access.
* **Tasks:**
  - [ ] Provide an `--offline` flag in `scripts/install.sh` that looks for local `sagemath-portable-<arch>.tar.zst` in the current directory instead of attempting network downloads.
