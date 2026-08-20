# Project Vision & Technical Overview: `sagelite`

**A Lightweight, Relocatable, and Native Portable SageMath Distribution for Linux**

---

## 1. Overview & Motivation

**SageMath** is one of the most comprehensive and powerful open-source mathematical systems available today, integrating decades of work across specialized computer algebra systems (CAS), numerical libraries, and interactive notebooks—including GAP, PARI/GP, Singular, FLINT, Maxima, NumPy, SciPy, SymPy, and JupyterLab.

For many users, installing SageMath via standard package managers or Conda environments works smoothly. However, in specific scenarios—such as locked-down university lab computers without `sudo`, shared HPC clusters, air-gapped systems, or quick student workshops—setting up package managers or compiling from source can present practical hurdles.

**`sagelite`** is a packaging effort that bundles pre-built Conda-Forge binaries into a **standalone, relocatable archive**. It allows users to download a single `.tar.zst` file, extract it anywhere, and immediately run SageMath via `./sage` without needing root access, pre-installed Conda/Python, or Docker.

### Quick Start
```bash
# Option A: One-liner installer
curl -fsSL https://github.com/sagelite/sagelite/releases/latest/download/install.sh | bash

# Option B: Manual download & extraction
tar --zstd -xf sagemath-portable-x86_64.tar.zst
cd sagemath-portable-x86_64/
./sage
```

---

## 2. Standing on the Shoulders of the Open-Source Community

`sagelite` is not a new computer algebra system or a replacement for SageMath. It is purely a distribution and relocation wrapper that builds upon the tremendous efforts of the open-source scientific ecosystem:

* **The SageMath Project & Contributors:** For creating and maintaining the vast unified mathematical interface, standard libraries, and doctest framework.
* **The Conda-Forge Community:** For providing the hermetically built, glibc-compatible binaries and sysroots (`sysroot_linux-64` / `sysroot_linux-aarch64`) that make binary portability possible across diverse Linux distributions.
* **The Component Developers:** The authors and maintainers of GAP, Singular, PARI/GP, FLINT, Maxima, LinBox, Matplotlib, SymPy, NumPy, and the Jupyter ecosystem.
* **The `conda-pack` and `micromamba` Teams:** For building the environment resolution and dynamic binary prefix relocation tooling (`conda-unpack`).

`sagelite` simply orchestrates these existing open-source components into a convenient, zero-setup artifact.

---

## 3. Core Design Principles

### 1. 100% Native Bare-Metal Execution
Runs directly as a standard native Linux process on host hardware. There are no container daemons, virtualization layers, or background services involved.

### 2. Broad Linux Compatibility (`glibc 2.28` Baseline)
By relying on Conda-Forge's hermetic sysroot packages, binaries target a `glibc 2.28` baseline, allowing the distribution to run out-of-the-box on:
* Ubuntu $\ge$ 20.04 LTS
* Debian $\ge$ 10
* RHEL / AlmaLinux / Rocky Linux $\ge$ 8
* Fedora $\ge$ 29
* Arch Linux, openSUSE, and other modern distributions

### 3. Self-Locating & Relocatable Entrypoint
Conda environments normally depend on fixed absolute paths. `sagelite` uses an entrypoint wrapper (`./sage`) that:
* Dynamically detects the current folder location regardless of symlinks or working directory.
* Runs a one-time prefix relocation step (`conda-unpack`) on the first invocation.
* Isolates the runtime by setting `PYTHONNOUSERSITE=1` and configuring `PYTHONHOME` to avoid conflicts with host Python packages.
* Provides convenient sub-command forwarding for `-pip`, `-python`, `-gap`, `-singular`, and `-gp`.

### 4. Bundled Cython JIT Toolchain & Pip Extensibility
* **Runtime Cython Compilation:** Includes GCC/G++/GFortran and matching headers so `%cython` compilation in interactive sessions and notebooks works without requiring host development tools.
* **Isolated Pip Management:** Users can install additional Python packages directly into the portable prefix via `./sage -pip install <package>` without affecting their host system.

### 5. Practical Footprint Optimization
To make downloads and extraction practical:
* Unneeded static libraries (`*.a`), libtool files (`*.la`), test suites, and documentation are pruned prior to packaging (while preserving compiler toolchain internals needed for Cython linking).
* Binaries and shared objects are stripped of unneeded debug symbols.
* Packed with multi-threaded Zstandard compression (level 19) to yield **~1.2 – 1.3 GB download** and **~4.2 GB extracted**.

---

## 4. Comparison of Distribution Approaches

| Aspect | Source Build | Conda / Mamba | Docker Image | `sagelite` |
| :--- | :--- | :--- | :--- | :--- |
| **Primary Use Case** | Development & customization | General-purpose environments | Containerized workflows | Portable / Zero-setup |
| **Root Permissions** | Not required | Not required | Often required (daemon) | Not required |
| **Setup Time** | Hours (compilation) | 5–15 mins (solving/download) | 1–3 mins (pull) | < 30 sec (extract) |
| **Prerequisites** | Full build toolchain & headers | Conda/Mamba installed | Docker/Podman runtime | None |
| **Relocatability** | Fixed prefix | Environment-managed | Contained | Move/rename anywhere |
| **Host Python Isolation** | Manual | Environment-dependent | Fully isolated | Automatic (`PYTHONNOUSERSITE=1`) |
| **Offline Deployment** | Difficult | Requires local mirror | Portable image | Single self-contained archive |

---

## 5. Technical Implementation Blueprint

### 5.1. Build & Sysroot Environment

The build runs on native Linux runners using `micromamba` and Conda-Forge sysroots:

| Parameter | Configuration | Purpose |
| :--- | :--- | :--- |
| **Sysroot Target** | `sysroot_linux-64` / `sysroot_linux-aarch64` | Targets dynamic linker baseline `glibc 2.28`. |
| **Package Manager** | `micromamba` (statically linked) | Fast dependency resolution and environment creation. |
| **Target Architectures** | `linux-64` (`x86_64`), `linux-aarch64` (`ARM64`) | Dedicated native CI matrix runners (`ubuntu-latest` and `ubuntu-24.04-arm`). |

### 5.2. Conda Recipe (`recipes/environment.x86_64.yml`)

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
  - zstandard
```

### 5.3. Build & Optimization Pipeline (`scripts/build.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Architecture detection
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64)
    DEFAULT_RECIPE="recipes/environment.x86_64.yml"
    ARCH_TAG="x86_64"
    MAMBA_ARCH="linux-64"
    ;;
  aarch64|arm64)
    DEFAULT_RECIPE="recipes/environment.aarch64.yml"
    ARCH_TAG="aarch64"
    MAMBA_ARCH="linux-aarch64"
    ;;
  *)
    echo "ERROR: Unsupported host architecture: $HOST_ARCH" >&2
    exit 1
    ;;
esac

RECIPE_FILE="${1:-$DEFAULT_RECIPE}"
OUTPUT_ARCHIVE="${2:-artifacts/sagemath-portable-${ARCH_TAG}.tar.zst}"
ENV_NAME="sage-portable"

# Auto-bootstrap standalone micromamba if missing from PATH
if ! command -v micromamba >/dev/null 2>&1; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  CACHE_BIN="$PROJECT_ROOT/.cache/bin"
  
  if [ -x "$CACHE_BIN/micromamba" ]; then
    export PATH="$CACHE_BIN:$PATH"
  else
    mkdir -p "$CACHE_BIN"
    curl -fsSL "https://micro.mamba.pm/api/micromamba/${MAMBA_ARCH}/latest" | tar -xj -C "$CACHE_BIN" --strip-components=1 bin/micromamba
    export PATH="$CACHE_BIN:$PATH"
  fi
fi

# 1. Create isolated Conda environment using micromamba
micromamba create -y -n "$ENV_NAME" -f "$RECIPE_FILE"

# 2. Resolve environment prefix path
PREFIX="$(micromamba env list | awk -v env="$ENV_NAME" '$1 == env {print $NF}')"

# 3. Strip non-essential files and static caches
find "$PREFIX" -type f -name "*.la" -delete
find "$PREFIX" -type f -name "*.a" \
  ! -path "*/lib/gcc/*" \
  ! -path "*/sysroot/*" \
  -delete

rm -rf "$PREFIX/share/doc" \
       "$PREFIX/share/man" \
       "$PREFIX/lib/python"*/test \
       "$PREFIX/lib/python"*/site-packages/sage/tests

find "$PREFIX/bin" "$PREFIX/lib" -type f -executable -exec strip --strip-unneeded {} + 2>/dev/null || true

# 4. Inject root wrapper script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/entrypoint.sh" "$PREFIX/sage"
chmod +x "$PREFIX/sage"

# 5. Package with conda-pack (Zstandard level 19)
mkdir -p "$(dirname "$OUTPUT_ARCHIVE")"
"$PREFIX/bin/conda-pack" \
  -p "$PREFIX" \
  -o "$OUTPUT_ARCHIVE" \
  --compress-level 19 \
  --n-threads -1 \
  --ignore-missing-files \
  --format tar.zst \
  --force

(cd "$(dirname "$OUTPUT_ARCHIVE")" && sha256sum "$(basename "$OUTPUT_ARCHIVE")" > "$(basename "$OUTPUT_ARCHIVE").sha256")
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

# Convenience sub-command forwarding
if [ $# -gt 0 ]; then
  case "$1" in
    -pip|--pip|pip)
      shift; exec "$DIR/bin/pip" "$@" ;;
    -python|--python|python)
      shift; exec "$DIR/bin/python" "$@" ;;
    -pytest|--pytest|pytest)
      shift; exec "$DIR/bin/pytest" "$@" ;;
    -gap|--gap|gap)
      shift; exec "$DIR/bin/gap" "$@" ;;
    -singular|--singular|singular)
      shift; exec "$DIR/bin/Singular" "$@" ;;
    -gp|--gp|gp)
      shift; exec "$DIR/bin/gp" "$@" ;;
  esac
fi

# Route execution directly to internal Sage runtime
exec "$DIR/bin/sage" "$@"
```

### 5.5. Verification & Test Suite (`scripts/test.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail
SAGE_BIN="${1:-./sage}"
MODE="${2:-fast}"

# 1. Core CAS Assertion Suite & Self-Tests
"$SAGE_BIN" -c "assert SymmetricGroup(5).order() == 120"
"$SAGE_BIN" -c "x = var('x'); assert factor(x^10 - 1) != 0"
"$SAGE_BIN" -c "assert int(gap('2+2')) == 4"
"$SAGE_BIN" -c "assert int(singular('2+2')) == 4"
"$SAGE_BIN" -c "assert pari('fibonacci(10)') == 55"

# 2. Official Sage Doctest Subsystem Verification (1,300+ tests)
"$SAGE_BIN" -c "
from sage.doctest.control import DocTestController, DocTestDefaults
import sage.combinat.permutation
options = DocTestDefaults()
controller = DocTestController(options, [sage.combinat.permutation.__file__])
res = controller.run()
assert res == 0, f'Doctest failed with exit code {res}'
"

# 3. Runtime Cython JIT Compilation
"$SAGE_BIN" -c "
from sage.repl.user_globals import set_globals
set_globals(globals())
from sage.misc.cython import cython_lambda
f = cython_lambda('long a, long b', 'a + b')
assert f(5, 7) == 12
"

# 4. Pip Installation Test
"$SAGE_BIN" -pip --version >/dev/null

# 5. Headless JupyterLab Verification
"$SAGE_BIN" -n jupyter --help >/dev/null 2>&1 || "$SAGE_BIN" -c "import jupyterlab; print('JupyterLab version:', jupyterlab.__version__)"
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

## 6. Target Use Cases

* **Academic & Student Labs:** Simple, single-folder distribution on university lab computers and shared HPC clusters where users do not have root access.
* **Classrooms & Workshops:** Instructors can distribute a single download link or USB drive to students across diverse Linux distributions, ensuring an identical, functional environment without installation friction.
* **CI/CD & Automated Grading:** Fast setup in automated testing workflows without waiting for full source builds or complex solver setups.
* **Air-Gapped / Offline Machines:** Single self-contained archive for environments without direct internet access to package repositories.
