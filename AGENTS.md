# AGENTS.md — Development & Operational Guidelines for `sagelite`

Welcome to **`sagelite`**. This document serves as the single source of truth, architectural guide, and operational manual for AI agents and developers working on this codebase.

---

## 1. Project Overview & Mission

**`sagelite`** is a zero-setup, relocatable, and fully portable SageMath distribution for Linux.

### Key Objectives:
* **Zero Host Prerequisites & No Containers:** Provide a single self-contained archive that runs natively on any modern Linux distribution without requiring root permissions, Docker/containers, system-level math libraries (GMP, MPFR, FLINT, Singular, GAP), or pre-installed Conda/Python.
* **glibc 2.28 Base Compatibility:** Target dynamic linker baseline `glibc 2.28` via Conda-Forge hermetic sysroots (compatible with Ubuntu $\ge$ 20.04, Debian $\ge$ 10, RHEL/Alma/Rocky 8+, Fedora $\ge$ 29, openSUSE, and Arch).
* **Embedded JIT Toolchain & Pip Extensibility:** Bundle a hermetic C/C++/Fortran compiler (`gcc`, `g++`, `gfortran`, headers) and `pip` so runtime Cython compilation (`%cython`) and adding Python packages work natively out of the box.
* **Official Test Framework Integration:** Support both fast smoke tests and official SageMath doctest execution (`sage.doctest` controller) to verify algebraic algorithms and CAS backends.
* **Self-Locating & Lazy-Unpacking:** Provide a zero-overhead `./sage` entrypoint that automatically resolves installation paths, handles binary prefix patching (`conda-unpack`) on first run, and sanitizes environment variables.
* **Optimized Payload:** Stripped footprint achieving **~1.2 – 1.3 GB** compressed (`.tar.zst`, Level 19) and **~4.2 GB** extracted.

---

## 2. Invariant Rules & Guardrails for Agents

When implementing features, fixing bugs, or updating recipes, you **MUST** uphold the following rules:

### 1. 100% Native Architecture (Zero Docker / Zero Containerization)
* **NEVER** introduce Docker, Podman, Singularity, or container runtime dependencies for end-user execution.
* The end-user artifact is a simple native directory containing native Linux executables, libraries, and the `./sage` entrypoint.
* Builds and CI pipelines run directly on native Linux runners using `micromamba` and `conda-pack`.

### 2. Hermetic Environment Isolation
* The runtime wrapper **MUST** prevent host Python and library pollution.
* Always enforce:
  * `PYTHONNOUSERSITE=1` (blocks `~/.local/lib/python*`)
  * `PYTHONHOME="$DIR"`
  * `SAGE_ROOT="$DIR"`
  * Isolated `$PATH` and `$LD_LIBRARY_PATH` prioritizing the bundled prefix.

### 3. Multi-Architecture Parity
* Support both `linux-64` (`x86_64`) and `linux-aarch64` (`ARM64`).
* Architecture-specific packages (e.g. `gcc_linux-64` vs `gcc_linux-aarch64`, `sysroot_linux-64` vs `sysroot_linux-aarch64`) must be dynamically parameterized or split into dedicated environment files.

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

When creating or modifying repository components, adhere to this layout:

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

## 4. Component Specifications

### 4.1. Conda Environment (`recipes/environment.x86_64.yml`)

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

> **Note for `aarch64`:** Replace `gcc_linux-64`, `gxx_linux-64`, `gfortran_linux-64`, `sysroot_linux-64` with `gcc_linux-aarch64`, `gxx_linux-aarch64`, `gfortran_linux-aarch64`, `sysroot_linux-aarch64`.

---

### 4.2. Build & Optimization Pipeline (`scripts/build.sh`)

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

---

### 4.3. Self-Locating Zero-Setup Entrypoint (`scripts/entrypoint.sh` $\rightarrow$ `./sage`)

```bash
#!/usr/bin/env bash
# Distribution root wrapper: sage
set -e

# Resolve directory location independent of invocation path or symlinks
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

# Run one-time binary dynamic prefix patching if not yet initialized
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

---

### 4.4. Verification Suite (`scripts/test.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

SAGE_BIN="${1:-./sage}"
MODE="${2:-fast}"

# 1. Core Algebra & CAS Backends (GAP, Singular, PARI/GP)
"$SAGE_BIN" -c "assert SymmetricGroup(5).order() == 120"
"$SAGE_BIN" -c "x = var('x'); assert factor(x^10 - 1) != 0"
"$SAGE_BIN" -c "assert int(gap('2+2')) == 4"
"$SAGE_BIN" -c "assert int(singular('2+2')) == 4"
"$SAGE_BIN" -c "assert pari('fibonacci(10)') == 55"

# 2. Official Sage Doctest Subsystem Verification (`sage.doctest`)
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

# 4. Pip Extensibility
"$SAGE_BIN" -pip --version >/dev/null

# 5. Headless Jupyter Server Verification
"$SAGE_BIN" -n jupyter --help >/dev/null 2>&1 || "$SAGE_BIN" -c "import jupyterlab; print('JupyterLab version:', jupyterlab.__version__)"
```

---

## 5. End-User Distribution Structure

The generated tarball unpacks into the following native directory structure:

```text
sagemath-portable-linux-x86_64/
├── sage                    # Unified self-locating entrypoint executable
├── bin/                    # Embedded binaries (python3, gap, Singular, gcc, pip)
├── include/                # Math headers (gmp.h, flint.h, Python.h)
├── lib/                    # Shared objects (.so) and Python site-packages
└── share/                  # CAS data libraries (gap/, singular/, jupyter/)
```

---

## 6. Operational Runbook for Agents

When requested to perform tasks in this repository:

1. **Native Shell Execution:** Ensure all scripts run natively with `set -euo pipefail` and clean error handling without container wrappers.
2. **Adding Dependencies:** When adding Python or math dependencies, verify compatibility in `recipes/environment.*.yml` without introducing heavy unneeded packages.
3. **Preserving Compiler Toolchain:** When writing size-reduction routines, **never** delete static files from `lib/gcc/*` or `sysroot/*` as they are essential for runtime Cython compilation.
4. **Validating Changes:** Run `./scripts/test.sh` against the extracted distribution to verify relocatability, algebra/Cython execution, and pip management.
5. **Inspecting Artifact Sizes:** Check size before and after any recipe modification to ensure extracted size stays within the target footprint.
