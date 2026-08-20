# Developer Guide: `sagelite`

This document details the build system, architecture, recipe configuration, and verification testing for contributors working on `sagelite`.

---

## 1. Architecture Overview

`sagelite` packages standard pre-compiled Conda-Forge packages into a relocatable native Linux directory.

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
3. **Payload Optimization (`scripts/build.sh`):** Reduces total uncompressed footprint from ~8 GB to ~4.2 GB.
4. **Relocation & Packaging (`conda-pack`):** Records prefix placeholders and compresses the tree with Zstandard level 19 into a ~1.3 GB archive.
5. **Entrypoint Wrapper (`scripts/entrypoint.sh`):** Resolves directory location dynamically, runs `conda-unpack` once on first launch, and sets runtime environment isolation variables.

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
# 1. Extract archive to a test directory
mkdir -p /tmp/test-sagelite
tar --zstd -xf artifacts/sagemath-portable-x86_64.tar.zst -C /tmp/test-sagelite

# 2. Run verification suite (~30 seconds)
./scripts/test.sh /tmp/test-sagelite/sage
```

### 4.2. Testing Relocatability

Verify that the distribution functions after being moved to a different path:

```bash
# Relocate directory
mv /tmp/test-sagelite /tmp/relocated-sagelite

# Execute tests from relocated path
./scripts/test.sh /tmp/relocated-sagelite/sage
```

### 4.3. Test Tiers Summary

| Tier | Test Scope | Verification Method |
| :--- | :--- | :--- |
| **1. CAS Backends** | GAP, Singular, PARI/GP | Evaluates basic algebra and group theory assertions |
| **2. Official Doctests** | `sage.doctest` subsystem | Executes 1,300+ official tests on core combinatorics & algebra modules |
| **3. Cython JIT** | Embedded compiler toolchain | Compiles and runs a dynamic C extension via `cython_lambda` |
| **4. Pip Extensibility** | Package management | Validates isolated `pip` binary |
| **5. JupyterLab** | Interactive notebook server | Verifies headless server startup |

To run the extended full doctest suite across all Sage modules:

```bash
./scripts/test.sh /tmp/relocated-sagelite/sage full
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
4. **Environment Isolation:** The `./sage` wrapper must enforce `PYTHONNOUSERSITE=1` and set `PYTHONHOME="$DIR"` to prevent host Python package pollution.

---

## 7. CI/CD Matrix Pipeline

The GitHub Actions workflow (`.github/workflows/build.yml`) builds and tests on native runners:
* `x86_64` on `ubuntu-latest`
* `aarch64` on `ubuntu-24.04-arm`
* Caches `~/.micromamba/pkgs` keyed by recipe hash.
* Tests directory extraction, relocation, and execution of `scripts/test.sh` on every build.
* On Git tags (`v*`), automatically publishes `.tar.zst` packages, SHA256 checksums, and `scripts/install.sh` to GitHub Releases.
