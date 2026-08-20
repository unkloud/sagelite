# sagelite

**Zero-Setup, Relocatable, and 100% Native Portable SageMath Distribution for Linux**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![glibc Compatibility](https://img.shields.io/badge/glibc-%E2%89%A5%202.28-green.svg)](docs/vision.md)
[![Platform](https://img.shields.io/badge/platform-linux--64%20%7C%20linux--aarch64-orange.svg)](docs/vision.md)

`sagelite` provides a single, portable, self-contained native distribution of **SageMath** for Linux. It extracts and runs instantly on virtually any modern Linux distribution—requiring **no root privileges**, **no Docker/containers**, **no pre-installed Conda/Python**, and **no external math libraries**.

---

## ⚡ Quick Start

### Option A: One-Liner Installation (Recommended)

Install `sagelite` directly to `~/.local/share/sagelite` and symlink `sage` into `~/.local/bin`:

```bash
curl -fsSL https://github.com/sagelite/sagelite/releases/latest/download/install.sh | bash
```

Once installed, launch SageMath from anywhere:

```bash
sage
```

Start the interactive **JupyterLab** notebook interface:

```bash
sage -n jupyter
```

---

### Option B: Manual Download & Extraction

1. Download the archive for your architecture from [GitHub Releases](https://github.com/sagelite/sagelite/releases):
   * **x86_64:** `sagemath-portable-x86_64.tar.zst`
   * **ARM64 (aarch64):** `sagemath-portable-aarch64.tar.zst`

2. Extract and run:

```bash
# Extract the archive anywhere
tar --zstd -xf sagemath-portable-x86_64.tar.zst
cd sagemath-portable-x86_64/

# Launch SageMath
./sage
```

---

## 🌟 Key Features

* **100% Native Bare-Metal Execution:** No Docker, Podman, Singularity, or container runtimes. Runs as a standard native Linux process with direct access to host files, GPUs, and networks.
* **Broad Linux Compatibility (`glibc 2.28`):** Works out-of-the-box on Ubuntu ($\ge$ 20.04), Debian ($\ge$ 10), RHEL/Alma/Rocky ($\ge$ 8), Fedora ($\ge$ 29), Arch Linux, and openSUSE.
* **Embedded Cython JIT Compiler:** Bundles a hermetic GCC, G++, GFortran, and sysroot headers so runtime Cython compilation (`%cython` in interactive sessions and notebooks) works seamlessly without installing host development tools.
* **Self-Locating & Relocatable:** Move or rename the extracted directory anywhere; the embedded `./sage` wrapper dynamically handles binary prefix patching (`conda-unpack`) on first execution.
* **Host Python Isolation:** Automatically sets `PYTHONNOUSERSITE=1` and isolates `PYTHONHOME` to prevent conflicts with host Python packages.
* **Built-in `pip` Extensibility:** Install additional Python packages directly into your portable instance:
  ```bash
  sage -pip install <package-name>
  ```
* **Lean Footprint:** Aggressively stripped of static archives (`*.a`), unneeded docs, and debug symbols to achieve **~1 GB download** and **~3.5 GB extracted**.
* **Architecture Parity:** First-class support for `x86_64` (Intel/AMD) and `aarch64` (ARM64 / Apple Silicon VMs / AWS Graviton).

---

## 🛠️ Building & Testing Locally

### Prerequisites
* `curl`, `tar`, `zstd`, `strip`

### 1. Build the Distribution

Run the native build script (automatically bootstraps `micromamba` into `.cache/bin/` if not present):

```bash
# Auto-detects architecture and builds archive in artifacts/
./scripts/build.sh
```

### 2. Run the Automated Test Suite

Extract the archive and run the 5-tier verification suite (validating CAS backends, official `sage -t` doctests, Cython JIT, Pip, and JupyterLab):

```bash
# Extract to a temporary directory
mkdir -p /tmp/test-sagelite
tar --zstd -xf artifacts/sagemath-portable-*.tar.zst -C /tmp/test-sagelite

# Run standard smoke and doctest suite (~30s)
./scripts/test.sh /tmp/test-sagelite/sage

# Optional: Run full official Sage doctest suite
./scripts/test.sh /tmp/test-sagelite/sage full
```

### 3. Verify Relocatability

Move the extracted folder to a new path and ensure it continues to function:

```bash
mv /tmp/test-sagelite /tmp/relocated-sagelite
./scripts/test.sh /tmp/relocated-sagelite/sage
```

---

## 🗑️ Uninstallation

If installed via `install.sh`:

```bash
./scripts/uninstall.sh
```

Or manually remove the directory and symlink:

```bash
rm -rf ~/.local/share/sagelite ~/.local/bin/sage
```

---

## 📄 License

`sagelite` is licensed under the [GNU General Public License v3.0 or later (GPL-3.0-or-later)](LICENSE), matching the SageMath license.
