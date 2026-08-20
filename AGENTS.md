# AGENTS.md — Development & Operational Guidelines for `sagelite`

This document serves as the operational guide, architectural specification, and guardrail manual for AI agents and human developers working on the **`sagelite`** repository.

---

## 1. Project Overview & Mission

**`sagelite`** is a zero-setup, relocatable, and 100% native portable SageMath distribution for Linux.

### Key Objectives:
* **Zero Host Prerequisites & No Containers:** Single self-contained archive that runs natively on any modern Linux distribution without requiring root privileges, Docker/containers, system-level math libraries (GMP, MPFR, FLINT, Singular, GAP), or pre-installed Conda/Python.
* **glibc 2.28 Base Compatibility:** Anchored to dynamic linker baseline `glibc 2.28` via Conda-Forge hermetic sysroots (compatible with Ubuntu $\ge$ 20.04, Debian $\ge$ 10, RHEL/Alma/Rocky 8+, Fedora $\ge$ 29, openSUSE, and Arch).
* **Embedded JIT Toolchain & Pip Extensibility:** Bundles a hermetic C/C++/Fortran compiler (`gcc`, `g++`, `gfortran`, headers) and `pip` so runtime Cython compilation (`%cython`) and adding Python packages work natively out of the box.
* **Official Test Framework Integration:** Validates CAS algorithms and backends using fast smoke tests and the official SageMath doctest runner (`sage.doctest` controller).
* **Self-Locating & Lazy-Unpacking:** Zero-overhead `./sage` entrypoint that automatically resolves installation paths, handles dynamic binary prefix patching (`conda-unpack`) on first run, and sanitizes environment variables.
* **Optimized Payload:** Stripped footprint achieving **~1.2 – 1.3 GB** compressed (`.tar.zst`, Level 19) and **~4.2 GB** extracted.

---

## 2. Invariant Rules & Guardrails for Agents

When implementing features, modifying recipes, or running builds, you **MUST** uphold the following rules:

### 1. 100% Native Architecture (Zero Docker / Zero Containerization)
* **NEVER** introduce Docker, Podman, Singularity, or container runtime dependencies.
* The end-user artifact is a simple native directory containing native Linux executables, libraries, and the `./sage` entrypoint.
* Builds and CI pipelines run directly on native Linux runners using `micromamba` and `conda-pack`.

### 2. Hermetic Environment Isolation
* The runtime wrapper **MUST** prevent host Python and library pollution. Always enforce:
  * `PYTHONNOUSERSITE=1` (blocks `~/.local/lib/python*`)
  * `PYTHONHOME="$DIR"`
  * `SAGE_ROOT="$DIR"`
  * Prepend `$DIR/bin` to `PATH` and `$DIR/lib` to `LD_LIBRARY_PATH`.

### 3. Multi-Architecture Parity
* First-class support for both `linux-64` (`x86_64`) and `linux-aarch64` (`ARM64`).
* Architecture-specific packages (e.g. `gcc_linux-64` vs `gcc_linux-aarch64`, `sysroot_linux-64` vs `sysroot_linux-aarch64`) must be dynamically handled or split into dedicated recipe files.

### 4. Aggressive Size Optimization & Toolchain Preservation
* Every build pipeline execution **MUST** strip unneeded artifacts prior to packaging:
  * Delete libtool metadata files (`*.la`).
  * Delete static archives (`*.a`), **EXCEPT** compiler toolchain internals (`lib/gcc/*` and `sysroot/*`), which are strictly required for Cython JIT linking.
  * Remove documentation and manual pages (`share/doc`, `share/man`).
  * Remove Python and Sage test suites (`lib/python*/test`, `lib/python*/site-packages/sage/tests`).
  * Strip unneeded symbols from binaries and `.so` files using `strip --strip-unneeded`.

### 5. Deterministic & Relocatable Packaging
* Archives **MUST** be packed with `conda-pack` using Zstandard level 19 compression (`--compress-level 19 --n-threads -1 --ignore-missing-files --format tar.zst`).
* Dynamic prefix relocation is automatically performed on the first user execution via the embedded `./sage` wrapper.

---

## 3. Repository Architecture & Layout

```text
sagelite/
├── .github/
│   └── workflows/
│       └── build.yml             # Native matrix CI/CD build & release pipeline (x86_64 & ARM64)
├── docs/
│   └── vision.md                 # Project vision, architecture & technical blueprint
├── recipes/
│   ├── environment.x86_64.yml    # Conda environment definition for x86_64
│   └── environment.aarch64.yml   # Conda environment definition for aarch64
├── scripts/
│   ├── build.sh                  # Native build & stripping script
│   ├── entrypoint.sh             # Template for the self-locating ./sage wrapper
│   ├── install.sh                # User-facing curl | bash one-liner install script
│   ├── uninstall.sh              # User-facing uninstallation script
│   └── test.sh                   # Verification suite (CAS, Cython, Jupyter, Pip, doctests)
├── .gitignore                    # Build artifacts and cache exclusions
├── LICENSE                       # GPL-3.0-or-later license
├── README.md                     # User documentation and quick-start guide
└── AGENTS.md                     # Agent development instructions (this file)
```

---

## 4. Operational Runbook

### 4.1. Local Build Workflow

```bash
# 1. Build the portable distribution (auto-detects architecture):
./scripts/build.sh

# 2. Or build with explicit recipe and custom output path:
./scripts/build.sh recipes/environment.x86_64.yml artifacts/sagemath-portable-x86_64.tar.zst
```

### 4.2. Local Verification & Relocation Testing

```bash
# 1. Extract to a test directory:
mkdir -p /tmp/test-sagelite
tar --zstd -xf artifacts/sagemath-portable-x86_64.tar.zst -C /tmp/test-sagelite

# 2. Relocate directory to verify dynamic path patching:
mv /tmp/test-sagelite /tmp/relocated-sagelite

# 3. Run the automated 5-tier verification suite (~30s):
./scripts/test.sh /tmp/relocated-sagelite/sage

# 4. (Optional) Run full official Sage doctest suite:
./scripts/test.sh /tmp/relocated-sagelite/sage full
```

### 4.3. Installing and Uninstalling

```bash
# Install to ~/.local/share/sagelite and symlink to ~/.local/bin/sage:
./scripts/install.sh

# Install to custom path:
./scripts/install.sh --dir=/opt/sagelite

# Uninstall:
./scripts/uninstall.sh -y
```

---

## 5. Technical Specifications & Critical Gotchas

### 5.1. Conda Recipe Guidelines
* **Channels:** Always specify `conda-forge` and `nodefaults`.
* **Sage Pin:** Use `sage = 10.*` wildcard to automatically track the latest stable 10.x release from Conda-Forge.
* **Python Pin:** Lock to `python = 3.12.*`.
* **Packaging Dependencies:** Ensure `conda-pack` and `zstandard` are present in dependencies so `conda-pack` can generate `.tar.zst` archives.

### 5.2. Payload Optimization & Stripping Gotchas
* **`libgcc.a` Preservation:** When removing static libraries (`*.a`), **never** delete static files from `lib/gcc/*` or `sysroot/*`. GCC's internal static runtimes are required when linking Cython extensions.
  ```bash
  find "$PREFIX" -type f -name "*.a" ! -path "*/lib/gcc/*" ! -path "*/sysroot/*" -delete
  ```
* **`conda-pack` Flag Requirement:** Always pass `--ignore-missing-files` and `--n-threads -1` to `conda-pack`. Because unneeded docs, tests, and static libraries were intentionally stripped, `conda-pack` will fail if `--ignore-missing-files` is omitted.

### 5.3. Entrypoint Wrapper Design
* **Sentinel File:** Dynamic prefix relocation (`conda-unpack`) is guarded by the sentinel file `$DIR/.unpacked`.
* **CLI Convenience Routing:** The `./sage` wrapper intercepts sub-commands to provide direct access to embedded utilities:
  * `./sage -pip ...` $\rightarrow$ `$DIR/bin/pip ...`
  * `./sage -python ...` $\rightarrow$ `$DIR/bin/python ...`
  * `./sage -gap ...` $\rightarrow$ `$DIR/bin/gap ...`
  * `./sage -singular ...` $\rightarrow$ `$DIR/bin/Singular ...`
  * `./sage -gp ...` $\rightarrow$ `$DIR/bin/gp ...`

### 5.4. Testing & Cython Evaluation in Non-Interactive Mode
* **Cython User Globals:** When compiling and executing Cython modules dynamically via `sage -c "..."`, Sage requires user-space globals to be initialized before module import:
  ```python
  from sage.repl.user_globals import set_globals
  set_globals(globals())
  from sage.misc.cython import cython_lambda
  f = cython_lambda('long a, long b', 'a + b')
  assert f(5, 7) == 12
  ```

---

## 6. Agent Quality & Verification Checklist

Before completing any task or committing changes, verify:

1. [ ] **Syntax Validation:** Run `bash -n scripts/*.sh` on all modified shell scripts.
2. [ ] **Error Handling:** All bash scripts contain `set -euo pipefail` and clean failure paths.
3. [ ] **Relocatability:** Tested extraction, directory movement (`mv`), and invocation from the moved directory.
4. [ ] **Verification Pass:** `./scripts/test.sh <path_to_sage>` executes with return code `0` across all 5 test tiers:
   * Core CAS backends (GAP, Singular, PARI/GP)
   * Official `sage.doctest` controller (1,300+ tests)
   * On-the-fly Cython JIT compilation (`%cython`)
   * Pip package management
   * Headless JupyterLab stack
5. [ ] **Size Bounds:** Archive size stays within **~1.2 – 1.3 GB** compressed and **~4.2 GB** extracted.
6. [ ] **Commit Signatures:** Ensure commits are cryptographically signed when committing changes.
