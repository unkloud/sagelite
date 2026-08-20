# Developer Guide for `sagelite`

This document details the build system, contribution workflow, recipe management, and testing infrastructure for developers working on the `sagelite` project.

---

## 1. Prerequisites

To build and package `sagelite` locally, your build machine requires:

* **Operating System:** Linux (`x86_64` or `aarch64`)
* **Standard Utilities:** `curl`, `tar`, `bzip2`, `zstd`, `strip`
* **Internet Access:** Connection to `conda-forge` repositories during build (the resulting archive is fully offline).

> Note: `micromamba` does not need to be installed on your system; `scripts/build.sh` automatically downloads a standalone `micromamba` binary into `.cache/bin/` if not found in `$PATH`.

---

## 2. Build Pipeline Architecture

```text
[recipes/environment.*.yml]
          │
          ▼  (micromamba create)
[$PREFIX (Staged Environment)]
          │
          ▼  (scripts/build.sh: Payload Optimization)
  - Remove *.la and non-compiler *.a
  - Remove share/doc, share/man, and test suites
  - Strip unneeded ELF symbols (strip --strip-unneeded)
  - Inject scripts/entrypoint.sh -> $PREFIX/sage
          │
          ▼  (conda-pack --compress-level 19 --ignore-missing-files)
[artifacts/sagemath-portable-<arch>.tar.zst]
```

---

## 3. Local Build Workflow

### 3.1. Auto-Detect Architecture & Build

The build script detects the host architecture (`uname -m`) and selects the appropriate recipe:

```bash
# Automatically builds artifacts/sagemath-portable-<arch>.tar.zst
./scripts/build.sh
```

### 3.2. Building for Specific Recipes or Output Paths

```bash
# Build with an explicit recipe and custom destination
./scripts/build.sh recipes/environment.x86_64.yml artifacts/custom-sage-x86_64.tar.zst
```

---

## 4. Verification & Testing Workflow

### 4.1. Automated 5-Tier Verification Suite

`scripts/test.sh` executes five validation tiers against a target Sage executable:

```bash
# Extract the built archive to a test directory
mkdir -p /tmp/test-sagelite
tar --zstd -xf artifacts/sagemath-portable-x86_64.tar.zst -C /tmp/test-sagelite

# Run the 5-tier test suite (~30 seconds)
./scripts/test.sh /tmp/test-sagelite/sage
```

### 4.2. Testing Relocatability

To verify that dynamic prefix patching (`conda-unpack`) works correctly when the distribution is moved:

```bash
# Relocate directory
mv /tmp/test-sagelite /tmp/relocated-sagelite

# Run tests from the relocated path
./scripts/test.sh /tmp/relocated-sagelite/sage
```

### 4.3. Test Tiers Overview

1. **Core Algebra & CAS Backends:** Validates GAP, Singular, and PARI/GP interfaces.
2. **Official Doctest Suite:** Runs `sage.doctest` controller on core algebra modules (1,300+ tests).
3. **Cython JIT Compilation:** Dynamically compiles a C extension using the bundled GCC toolchain.
4. **Pip Extensibility:** Checks that the isolated `pip` binary is functional.
5. **JupyterLab Stack:** Validates headless startup of the notebook server.

To run the extended full doctest suite across all modules:

```bash
./scripts/test.sh /tmp/relocated-sagelite/sage full
```

---

## 5. Recipe Management Guidelines

Environment recipes are located in `recipes/`:
* `recipes/environment.x86_64.yml`: Package definitions for Intel/AMD 64-bit architectures.
* `recipes/environment.aarch64.yml`: Package definitions for ARM64 architectures.

### Package Selection Rules
1. **SageMath Wildcard:** Pin SageMath using `sage = 10.*` to track stable 10.x releases from Conda-Forge.
2. **Python Version:** Locked to `python = 3.12.*`.
3. **Compiler Toolchains:**
   * For `x86_64`: `gcc_linux-64`, `gxx_linux-64`, `gfortran_linux-64`, `sysroot_linux-64`.
   * For `aarch64`: `gcc_linux-aarch64`, `gxx_linux-aarch64`, `gfortran_linux-aarch64`, `sysroot_linux-aarch64`.
4. **Relocation & Compression Packages:** Ensure `conda-pack` and `zstandard` are present in dependencies.

---

## 6. Critical Technical Invariants

* **Preserving Compiler Runtimes:** When stripping static libraries in `scripts/build.sh`, never delete static files under `lib/gcc/*` or `sysroot/*`. These static archives (such as `libgcc.a`) are required by GCC/ld when compiling Cython extensions at runtime.
* **Conda-Pack Flags:** Always invoke `conda-pack` with `--ignore-missing-files` because non-essential files are intentionally stripped before packaging.
* **Runtime Isolation:** The `./sage` wrapper must enforce `PYTHONNOUSERSITE=1` and set `PYTHONHOME="$DIR"` to guarantee complete isolation from host Python packages.

---

## 7. CI/CD Matrix Pipeline

The GitHub Actions workflow (`.github/workflows/build.yml`) builds and tests on native runners:

* **`x86_64`:** Runs on `ubuntu-latest`.
* **`aarch64`:** Runs on `ubuntu-24.04-arm`.
* **Caching:** Caches `~/.micromamba/pkgs` keyed by recipe hash.
* **Verification:** Automatically extracts, relocates, and executes `scripts/test.sh` on every build.
* **Releases:** On git tag pushes matching `v*`, automatically bundles `.tar.zst` packages, SHA256 checksums, and `scripts/install.sh` into a GitHub Release.
