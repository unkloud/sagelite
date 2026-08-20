# sagelite

A lightweight, zero-setup, and portable SageMath distribution for Linux.

`sagelite` packages standard pre-compiled Conda-Forge binaries into a standalone, relocatable archive. It extracts and runs on modern Linux distributions without requiring root privileges, Docker or containers, pre-installed Python/Conda environments, or host development libraries.

---

## 1. Quick Start

### Automated Installation (Recommended)

Installs `sagelite` to `~/.local/share/sagelite` and symlinks `sage` into `~/.local/bin`:

```bash
curl -fsSL https://github.com/sagelite/sagelite/releases/latest/download/install.sh | bash
```

To install to a custom directory:

```bash
curl -fsSL https://github.com/sagelite/sagelite/releases/latest/download/install.sh | bash -s -- --dir=/opt/sagelite
```

### Manual Download & Extraction

1. Download the archive for your architecture from GitHub Releases:
   * **x86_64:** `sagemath-portable-x86_64.tar.zst`
   * **ARM64 (aarch64):** `sagemath-portable-aarch64.tar.zst`

2. Extract and run from any directory:

```bash
tar --zstd -xf sagemath-portable-x86_64.tar.zst
cd sagemath-portable-x86_64/
./sage
```

---

## 2. System Requirements

* **Operating System:** Linux (Kernel $\ge$ 3.2)
* **Architecture:** `x86_64` (Intel/AMD 64-bit) or `aarch64` (ARM64)
* **C Library Compatibility:** `glibc >= 2.28` (compatible with Ubuntu $\ge$ 20.04, Debian $\ge$ 10, RHEL / Rocky / Alma $\ge$ 8, Fedora $\ge$ 29, openSUSE, and Arch Linux).
* **Storage:** ~1.3 GB download archive; ~4.2 GB extracted disk space.

---

## 3. Usage Guide

### Interactive Shell (REPL)

```bash
sage
```

Example session:

```text
sage: E = EllipticCurve([0, 0, 0, -4, 0])
sage: E.conductor()
32
sage: E.rank()
1
```

### JupyterLab Notebooks

Launch the integrated JupyterLab notebook server:

```bash
sage -n jupyter
```

SageMath kernels and interactive widgets (`ipywidgets`) are pre-configured.

### Non-Interactive Command Evaluation

```bash
# Evaluate an inline mathematical expression
sage -c "print(factor(x^10 - 1))"

# Run a Sage script
sage script.sage

# Run a Python script using the bundled runtime
sage -python script.py
```

### Adding Python Packages (`pip`)

`sagelite` includes an isolated `pip` package manager. You can install Python packages directly into your portable instance:

```bash
sage -pip install <package-name>
sage -pip list
```

### Runtime Cython Compilation (`%cython`)

`sagelite` bundles GCC, G++, GFortran, and system headers. Compiling C extensions on-the-fly works out-of-the-box in notebooks and interactive sessions without installing host build tools:

```python
%cython
def fast_collatz(long n):
    cdef long steps = 0
    while n > 1:
        if n % 2 == 0:
            n = n // 2
        else:
            n = 3 * n + 1
        steps += 1
    return steps
```

### Direct Subsystem Access

The `./sage` wrapper provides direct access to embedded CAS engines:

```bash
sage -gap          # Standalone GAP session
sage -singular     # Standalone Singular session
sage -gp           # Standalone PARI/GP session
sage -pytest       # Run pytest in the bundled environment
```

---

## 4. Distribution Comparison

| Aspect | Source Build | Conda / Mamba | Docker Image | `sagelite` |
| :--- | :--- | :--- | :--- | :--- |
| **Setup Method** | Compile from source | Install via package manager | Pull container image | Extract archive |
| **Setup Time** | Hours | 5–15 minutes | 1–3 minutes | < 30 seconds |
| **Root Required** | No | No | Usually (daemon) | No |
| **Dependencies** | Full host toolchain | Conda/Mamba | Docker/Podman runtime | None |
| **Relocatable** | No (fixed path) | Environment-bound | Containerized | Move/rename anywhere |
| **Host Python Isolation** | Manual | Environment-dependent | Contained | Automatic (`PYTHONNOUSERSITE=1`) |
| **Offline Ready** | No | Requires local mirror | Yes | Single file |

---

## 5. Key Concepts & Terminology

| Term | Definition |
| :--- | :--- |
| **CAS (Computer Algebra System)** | Software for symbolic mathematical calculations (e.g. GAP for group theory, Singular for polynomial algebra, PARI/GP for number theory). |
| **`glibc`** | The GNU C Library standard runtime on Linux. `sagelite` targets `glibc 2.28` to ensure binary compatibility across all major Linux distributions released since 2019. |
| **Sysroot** | A self-contained set of header files and standard libraries used by the compiler to build binaries against a specific target `glibc` baseline. |
| **Prefix Relocation** | The process of updating hardcoded directory paths in binaries and script shebangs (`#!/path/to/python`) when an application is moved to a new directory. `sagelite` handles this automatically on first run via `conda-unpack`. |
| **Cython JIT** | Just-In-Time compilation of Cython/C code directly inside interactive Sage sessions or Jupyter notebook cells (`%cython`). |
| **Zstandard (`.tar.zst`)** | A modern compression format providing high compression ratios and fast decompression speeds. |
| **`PYTHONNOUSERSITE`** | An environment variable that prevents Python from loading user packages from `~/.local/lib/python*`, avoiding conflicts between host packages and the bundled SageMath runtime. |

---

## 6. Troubleshooting

### `sage: command not found`
Add `~/.local/bin` to your `$PATH`:
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### `tar: --zstd: unknown option` or extraction failure
Install `zstd` using your system package manager:
* **Ubuntu / Debian:** `sudo apt install zstd`
* **RHEL / Rocky / Alma / Fedora:** `sudo dnf install zstd`
* **Arch Linux:** `sudo pacman -S zstd`

Then extract with:
```bash
zstd -d -c sagemath-portable-x86_64.tar.zst | tar -xf -
```

### `version 'GLIBC_2.28' not found`
`sagelite` requires `glibc >= 2.28`. Operating systems older than Ubuntu 20.04, Debian 10, or RHEL 8 cannot run the pre-built binaries.

### Conflicts with host Python packages
The `./sage` wrapper isolates `PYTHONHOME` and ignores user site-packages automatically. If you have a custom `PYTHONPATH` set in your shell, unset it before running Sage:
```bash
unset PYTHONPATH
sage
```

### Relocating the directory
You can move or rename the extracted directory at any time. The wrapper detects the new location and re-applies path patching automatically on the next run.

---

## 7. Uninstallation

If installed via `install.sh`:
```bash
./scripts/uninstall.sh
```

Or manually remove the directory and symlink:
```bash
rm -rf ~/.local/share/sagelite ~/.local/bin/sage
```

---

## 8. Documentation & Development

* **Developer Guide:** See [docs/development.md](docs/development.md) for local builds, recipe customization, and testing workflows.
* **Agent Guidelines:** See [AGENTS.md](AGENTS.md) for automated workflows, operational guardrails, and coding standards.

---

## 9. License & Acknowledgments

`sagelite` is licensed under the [GNU General Public License v3.0 or later (GPL-3.0-or-later)](LICENSE).

`sagelite` builds directly upon the work of the **SageMath Project**, the **Conda-Forge Community**, and the authors of GAP, Singular, PARI/GP, FLINT, Maxima, LinBox, Matplotlib, SymPy, NumPy, and JupyterLab.
