# Project Vision & Technical Blueprint: `sagelite`

**Zero-Setup, Relocatable, and Native Portable SageMath Distribution for Linux**

---

## 1. Executive Summary

**`sagelite`** solves one of the longest-standing usability challenges in scientific and mathematical computing: **the friction of deploying and running SageMath on Linux**.

SageMath is a comprehensive mathematical ecosystem combining dozens of specialized computer algebra systems (CAS), numerical libraries, and interactive interfaces (GAP, PARI/GP, Singular, FLINT, Maxima, NumPy, SymPy, JupyterLab). However, installing and distributing SageMath traditionally demands extensive compilation time, complex package manager setup, or administrative permissions.

`sagelite` provides a **single, portable, self-contained native archive** that extracts and runs instantly on virtually any modern Linux distribution—requiring **no root privileges**, **no Docker or container runtimes**, **no pre-installed Conda/Python**, **no system-level math libraries**, and **no external compilation toolchain**.

### Quick Start
```bash
# Option A: One-liner automated installation
curl -fsSL https://github.com/sagelite/sagelite/releases/latest/download/install.sh | bash

# Option B: Manual extraction
tar --zstd -xf sagemath-portable-x86_64.tar.zst
cd sagemath-portable-x86_64/
./sage
```

---

## 2. The Problem Statement

| Distribution Method | Key Limitations & Pain Points |
| :--- | :--- |
| **Source Compilation** | Takes 2–6+ hours to build; frequently breaks due to host toolchain drift, compiler mismatches, or missing build prerequisites. |
| **System Package Managers (`apt`, `dnf`, `pacman`)** | Often severely outdated, split across dozens of disjoint packages, or completely unavailable on enterprise/LTS distributions. |
| **Standard Conda/Mamba Environments** | Requires users to install Conda/Mamba first; suffers from slow solver times, metadata overhead, and file sprawl (100,000+ files) that degrades performance on shared network filesystems (NFS). |
| **Docker / Containers (Traditional Workaround)** | Heavy overhead; requires root/Docker daemon access; introduces container isolation friction (port forwarding, volume permission mismatches, X11/GUI passthrough issues). |

---

## 3. Core Design Pillars

`sagelite` is engineered around six foundational pillars:

### 1. 100% Native Execution (Zero Containers / Zero Docker)
* **Bare-Metal Direct Process:** Runs as a standard native Linux process directly on host hardware with direct access to local files, GPUs, and networks.
* **No Daemons or Virtualization:** No Docker, Podman, Singularity, chroot, or background daemons required at runtime or build time.

### 2. Universal Linux Portability (`glibc 2.28` Baseline)
By leveraging Conda-Forge's hermetic sysroot (`sysroot_linux-64` / `sysroot_linux-aarch64`), all binaries and shared libraries target a **`glibc 2.28`** baseline. This guarantees native out-of-the-box execution across:
* **Ubuntu** $\ge$ 20.04 LTS
* **Debian** $\ge$ 10 (Buster, Bullseye, Bookworm)
* **RHEL / CentOS / AlmaLinux / Rocky Linux** $\ge$ 8
* **Fedora** $\ge$ 29
* **Arch Linux** and **openSUSE** (Leap & Tumbleweed)

### 3. Zero-Setup Relocatability & Self-Healing Entrypoint
Traditional Python/Conda environments hardcode absolute prefix paths. `sagelite` embeds an intelligent root wrapper script (`./sage`) that:
* Dynamically detects its installation path regardless of symlinks or working directory.
* Runs a one-time binary prefix relocation (`conda-unpack`) on first execution without user intervention.
* Sanitizes the environment (`PYTHONNOUSERSITE=1`, isolated `PYTHONHOME` and library paths) to prevent conflicts with host Python packages.

### 4. Embedded JIT Compilation Toolchain & Pip Extensibility
* **Hermetic Cython Toolchain:** Bundles GCC/G++/GFortran and sysroot headers, enabling full C/Cython JIT compilation (`%cython` cells) without any host development packages.
* **Direct Pip Extensibility:** Includes `pip` within the distribution, allowing users to install additional Python packages directly into their portable instance via `./sage -pip install <package>` without affecting the host OS.

### 5. Optimized & Lean Footprint
Full SageMath installations often exceed 8–10 GB. `sagelite` aggressively streamlines the payload:
* Prunes duplicate static libraries (`*.a`), libtool files (`*.la`), test suites, and documentation.
* Strips unneeded debug symbols from native binaries and shared objects (`.so`).
* Compresses the distribution with multi-threaded **Zstandard Level 19** (`.tar.zst`).
* **Footprint Target:** **~900 MB – 1.2 GB** download size $\rightarrow$ **~3.2 – 3.8 GB** extracted.

### 6. Full Mathematical & Notebook Stack with Multi-Arch Parity
* Includes full CAS backends (GAP, Singular, PARI/GP, FLINT, Maxima), standard scientific libraries (NumPy, SciPy, Matplotlib, SymPy), and modern interactive notebook support (**JupyterLab**, `ipywidgets`).
* First-class support for both **`linux-64` (`x86_64`)** and **`linux-aarch64` (`ARM64`)**, ensuring seamless deployment on cloud instances (e.g. AWS Graviton), Apple Silicon Linux VMs, and modern ARM servers.

---

## 4. Architectural Comparison

```
+------------------------+-------------+-------------+---------------+--------------+
| Feature                |  Source     | Conda/Mamba | Docker        |  sagelite    |
+------------------------+-------------+-------------+---------------+--------------+
| Zero Root Required     |      X      |      ✓      |       X       |      ✓       |
| No Pre-installed Tools |      X      |      X      |       X       |      ✓       |
| No Container/Daemon    |      ✓      |      ✓      |       X       |      ✓       |
| Install Time           |  2-6 hours  |  5-15 mins  |   1-3 mins    |   < 30 sec   |
| Relocatable Folder     |      X      |      X      |      N/A      |      ✓       |
| Host Python Isolation  |      X      |  Partial    |       ✓       |      ✓       |
| Embedded Cython JIT    |  Requires   |  Requires   |   Container   |   Bundled    |
|                        |  host gcc   |  host/extra |   contained   |   out-of-box |
| Runtime Pip Install    |  Difficult  |  Supported  |  Requires     |   Bundled    |
|                        |             |             |  new image    |  (isolated)  |
| Official Test Suite    |  Full       |  Full       |   Full        |  `sage -t`   |
|                        |  (Slow)     |  (Slow)     |   (Slow)      |  (Targeted)  |
| Offline / Air-Gapped   |      X      |      X      |       ✓       |      ✓       |
+------------------------+-------------+-------------+---------------+--------------+
```

---

## 5. Technical Implementation Blueprint

### 5.1. Build Environment & Sysroot Anchoring

The build executes natively on Linux CI runners using `micromamba` with pre-anchored sysroots:

| Parameter | Configuration | Purpose |
| --- | --- | --- |
| **Sysroot Target** | `sysroot_linux-64` / `sysroot_linux-aarch64` | Locks dynamic linker baseline to **`glibc 2.28`**. |
| **Package Manager** | `micromamba` (statically linked) | Rapid, deterministic dependency resolution. |
| **Target Architectures** | `linux-64` (`x86_64`), `linux-aarch64` (`ARM64`) | Dedicated native CI matrix runners (`ubuntu-latest` and `ubuntu-24.04-arm`). |

### 5.2. Environment Specification (`recipes/environment.x86_64.yml`)

```yaml
name: sage-portable
channels:
  - conda-forge
  - nodefaults
dependencies:
  # Core System & SageMath
  - sage = 10.*
  - python = 3.12.*
  - pip
  
  # Interactive Notebook UI
  - jupyterlab
  - ipywidgets
  
  # Runtime Cython & Compilation Toolchain (for %cython cells)
  - cython >= 3.0
  - gcc_linux-64
  - gxx_linux-64
  - gfortran_linux-64
  - sysroot_linux-64
  - pkg-config
  
  # Packaging & Relocation Utilities
  - conda-pack
```

### 5.3. Build & Optimization Pipeline (`scripts/build.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

RECIPE_FILE="${1:-recipes/environment.x86_64.yml}"
OUTPUT_ARCHIVE="${2:-artifacts/sagemath-portable-x86_64.tar.zst}"
ENV_NAME="sage-portable"

# 1. Create isolated Conda environment using micromamba
micromamba create -y -n "$ENV_NAME" -f "$RECIPE_FILE"

# 2. Activate environment
eval "$(micromamba shell hook --shell bash)"
micromamba activate "$ENV_NAME"
PREFIX="$MAMBA_ROOT_PREFIX/envs/$ENV_NAME"

# 3. Strip non-essential files and static caches
find "$PREFIX" -type f \( -name "*.a" -o -name "*.la" \) -delete
rm -rf "$PREFIX/share/doc" \
       "$PREFIX/share/man" \
       "$PREFIX/lib/python"*/test \
       "$PREFIX/lib/python"*/site-packages/sage/tests

# 4. Strip unneeded symbols from binaries and shared objects
find "$PREFIX/bin" "$PREFIX/lib" -type f -executable -exec strip --strip-unneeded {} + 2>/dev/null || true

# 5. Inject root wrapper script
cp scripts/entrypoint.sh "$PREFIX/sage"
chmod +x "$PREFIX/sage"

# 6. Package with conda-pack (Zstandard level 19)
mkdir -p "$(dirname "$OUTPUT_ARCHIVE")"
conda-pack -p "$PREFIX" -o "$OUTPUT_ARCHIVE" --compress-level 19 --format tar.zst
```

### 5.4. Self-Locating Zero-Setup Entrypoint (`scripts/entrypoint.sh` $\rightarrow$ `./sage`)

```bash
#!/usr/bin/env bash
set -e

# Resolve directory location independent of invocation path or symlinks
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

# Run one-time binary dynamic prefix patching on first launch
if [ ! -f "$DIR/.unpacked" ]; then
  if [ -f "$DIR/bin/conda-unpack" ]; then
    "$DIR/bin/python" "$DIR/bin/conda-unpack" >/dev/null 2>&1 || true
    touch "$DIR/.unpacked"
  fi
fi

# Sanitize environment to prevent host Python pollution
export SAGE_ROOT="$DIR"
export PYTHONNOUSERSITE=1
export PYTHONHOME="$DIR"
export PATH="$DIR/bin:$PATH"
export LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Route execution directly to internal Sage runtime
exec "$DIR/bin/sage" "$@"
```

### 5.5. Verification & Test Suite (`scripts/test.sh`)

Supports both fast CI smoke testing and official Sage doctest runner (`sage -t`):

```bash
#!/usr/bin/env bash
set -euo pipefail
SAGE_BIN="${1:-./sage}"
MODE="${2:-fast}"

echo "==> Testing SageMath executable: $SAGE_BIN (Mode: $MODE)"

# 1. Core CAS Assertion Suite & Self-Tests
"$SAGE_BIN" -c "assert SymmetricGroup(5).order() == 120"
"$SAGE_BIN" -c "assert factor(x^10 - 1) != 0"
"$SAGE_BIN" -c "assert pari('fibonacci(10)') == 55"
"$SAGE_BIN" -c "gap._test(); singular._test(); pari._test()"

# 2. Official Sage Doctest Subsystem Verification (`sage -t`)
"$SAGE_BIN" -t $("$SAGE_BIN" -c "import sage.libs.pari.pari_instance as m; print(m.__file__)")
"$SAGE_BIN" -t $("$SAGE_BIN" -c "import sage.rings.polynomial.multi_polynomial_libsingular as m; print(m.__file__)")

# 3. Runtime Cython JIT Compilation
"$SAGE_BIN" -c '
%cython
def fast_add(long a, long b):
    return a + b
assert fast_add(5, 7) == 12
'

# 4. Pip Installation Test
"$SAGE_BIN" -pip --version >/dev/null

# 5. Headless JupyterLab Verification
"$SAGE_BIN" -n jupyter --help >/dev/null 2>&1 || "$SAGE_BIN" --jupyter --version >/dev/null

if [ "$MODE" = "full" ]; then
    echo "==> Running full SageMath doctest test suite (sage -t -p $(nproc) --all)..."
    "$SAGE_BIN" -t -p "$(nproc)" --all || true
fi
```

### 5.6. End-User Distribution Structure

```text
sagemath-portable-linux-x86_64/
├── sage                    # Unified self-locating entrypoint executable
├── bin/                    # Embedded binaries (python3, gap, Singular, gcc, pip)
├── include/                # Math headers (gmp.h, flint.h, Python.h)
├── lib/                    # Shared objects (.so) and Python site-packages
└── share/                  # CAS data libraries (gap/, singular/, jupyter/)
```

---

## 6. Target Use Cases & Personas

* **Academic & Student Environments:** Instant deployment on locked-down university laboratory computers and High-Performance Computing (HPC) clusters where students/researchers do not have `sudo` privileges.
* **Classroom & Workshops:** Instructors can distribute a single USB drive or download link to dozens of students with diverse Linux distributions, ensuring everyone runs an identical, reproducible SageMath environment without installing software.
* **CI/CD & Automated Grading:** Headless, lightning-fast setup in automated grading systems and CI workflows without building from source, installing container daemons, or waiting for Conda solves.
* **Offline / Air-Gapped Systems:** Complete self-contained artifact for secure, offline environments where internet access to package repositories is restricted.
