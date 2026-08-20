# sagelite

A zero-setup, relocatable, and native portable SageMath distribution for Linux.

`sagelite` provides a self-contained distribution of SageMath that runs out-of-the-box on modern Linux distributions without requiring root privileges, Docker or containers, pre-installed Conda/Python environments, or external math libraries.

---

## 1. System Requirements

* **Operating System:** Linux (Kernel $\ge$ 3.2)
* **Architecture:** `x86_64` (Intel/AMD 64-bit) or `aarch64` (ARM64)
* **C Library Compatibility:** Dynamic linker baseline `glibc >= 2.28`
  * Compatible with Ubuntu $\ge$ 20.04, Debian $\ge$ 10, RHEL / CentOS / Alma / Rocky $\ge$ 8, Fedora $\ge$ 29, openSUSE, and Arch Linux.
* **Storage:** ~1.3 GB for download archive; ~4.2 GB extracted disk space.

---

## 2. Installation

### 2.1. Automated Installation (Recommended)

Run the one-liner installer to download the latest release for your architecture, extract it to `~/.local/share/sagelite`, and symlink `sage` into `~/.local/bin`:

```bash
curl -fsSL https://github.com/sagelite/sagelite/releases/latest/download/install.sh | bash
```

To install to a custom directory:

```bash
curl -fsSL https://github.com/sagelite/sagelite/releases/latest/download/install.sh | bash -s -- --dir=/opt/sagelite
```

### 2.2. Manual Download & Extraction

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

## 3. User Manual & Usage Guide

### 3.1. Interactive SageMath Shell (REPL)

Launch the interactive SageMath prompt:

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

### 3.2. Launching JupyterLab Notebooks

Start the integrated JupyterLab notebook server:

```bash
sage -n jupyter
```

SageMath kernels and interactive widgets (`ipywidgets`) are pre-configured out-of-the-box.

### 3.3. Non-Interactive Command Evaluation

Execute one-off SageMath commands or mathematical scripts:

```bash
# Evaluate an inline expression
sage -c "print(factor(x^10 - 1))"

# Execute a SageMath script
sage script.sage

# Execute a Python script using the bundled runtime
sage -python script.py
```

### 3.4. Extending with Python Packages (`pip`)

`sagelite` includes an isolated `pip` package manager. You can install Python packages directly into your portable instance without affecting host system libraries:

```bash
# Install a package
sage -pip install sympy-plot-backends

# Upgrade a package
sage -pip install --upgrade scipy

# List installed packages
sage -pip list
```

### 3.5. Runtime Cython Compilation (`%cython`)

`sagelite` bundles a hermetic C/C++/Fortran compiler (`gcc`, `g++`, `gfortran`, and sysroot headers). Runtime compilation of Cython code works natively in both notebooks and scripts without installing host build packages.

In Jupyter notebooks or interactive sessions:

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

### 3.6. Direct Subsystem Access

The `./sage` entrypoint provides direct access to embedded CAS binaries:

```bash
sage -gap          # Launch standalone GAP session
sage -singular     # Launch standalone Singular session
sage -gp           # Launch standalone PARI/GP session
sage -pytest       # Run pytest in the bundled environment
```

---

## 4. Troubleshooting Guide

### 4.1. `sage: command not found`

**Cause:** The directory `~/.local/bin` is not present in your shell's `$PATH` environment variable.

**Solution:** Add `~/.local/bin` to your `$PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

To make this permanent, add the line above to your `~/.bashrc` or `~/.zshrc` file:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

### 4.2. `tar: --zstd: unknown option` or extraction failure

**Cause:** The installed version of `tar` on your system does not have built-in Zstandard support.

**Solution:** Install `zstd` using your system package manager:

* **Ubuntu / Debian:** `sudo apt install zstd`
* **RHEL / Rocky / Alma / Fedora:** `sudo dnf install zstd`
* **Arch Linux:** `sudo pacman -S zstd`

Once installed, extract using:

```bash
zstd -d -c sagemath-portable-x86_64.tar.zst | tar -xf -
```

---

### 4.3. `version 'GLIBC_2.28' not found`

**Cause:** The host operating system uses a glibc version older than `2.28` (such as Ubuntu 18.04 or CentOS 7).

**Solution:** `sagelite` requires Linux distributions with `glibc >= 2.28`. Upgrade the host operating system to a supported version (e.g. Ubuntu $\ge$ 20.04, Debian $\ge$ 10, RHEL $\ge$ 8).

---

### 4.4. Conflicts with Host Python or Virtual Environments

**Cause:** Host `PYTHONPATH` or user-site packages interfering with SageMath libraries.

**Solution:** The `./sage` wrapper automatically sets `PYTHONNOUSERSITE=1` and isolates `PYTHONHOME`. If you have a custom `PYTHONPATH` exported in your shell, unset it prior to running Sage:

```bash
unset PYTHONPATH
sage
```

---

### 4.5. Relocating or Moving the Directory

If you move or rename the extracted `sagelite` directory, the wrapper automatically re-applies dynamic binary prefix relocation (`conda-unpack`) on the first run from the new path. No manual intervention is needed.

---

## 5. Uninstallation

If installed via the automated script:

```bash
./scripts/uninstall.sh
```

Or manually remove the installation folder and executable symlink:

```bash
rm -rf ~/.local/share/sagelite ~/.local/bin/sage
```

---

## 6. Developer & Contributor Resources

* **Developer Guide:** See [docs/development.md](docs/development.md) for local build workflows, recipe customization, and testing procedures.
* **Architecture & Vision:** See [docs/vision.md](docs/vision.md) for design pillars, community credits, and sysroot anchoring details.
* **Agent Guidelines:** See [AGENTS.md](AGENTS.md) for AI coding agent invariants and operational runbooks.

---

## 7. License & Acknowledgments

`sagelite` is licensed under the [GNU General Public License v3.0 or later (GPL-3.0-or-later)](LICENSE).

`sagelite` builds upon the work of the **SageMath Project**, the **Conda-Forge Community**, and the developers of GAP, Singular, PARI/GP, FLINT, Maxima, LinBox, and JupyterLab.
