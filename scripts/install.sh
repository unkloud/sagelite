#!/usr/bin/env bash
set -euo pipefail

# Configuration defaults
REPO="${SAGELITE_REPO:-${GITHUB_REPOSITORY:-sagelite/sagelite}}"
DEFAULT_INSTALL_DIR="$HOME/.local/share/sagelite"
BIN_DIR="$HOME/.local/bin"
VERSION="latest"
INSTALL_DIR="$DEFAULT_INSTALL_DIR"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir=*|-d=*)
      INSTALL_DIR="${1#*=}"
      shift
      ;;
    --dir|-d)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --version=*|-v=*)
      VERSION="${1#*=}"
      shift
      ;;
    --version|-v)
      VERSION="$2"
      shift 2
      ;;
    --repo=*)
      REPO="${1#*=}"
      shift
      ;;
    --help|-h)
      echo "sagelite installer"
      echo ""
      echo "Usage: curl -fsSL https://.../install.sh | bash -s -- [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -d, --dir=PATH      Installation target directory (default: ~/.local/share/sagelite)"
      echo "  -v, --version=TAG   Release version tag (default: latest)"
      echo "  --repo=OWNER/REPO   GitHub repository (default: sagelite/sagelite)"
      echo "  -h, --help          Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Architecture detection
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64)
    ARCH_TAG="x86_64"
    ;;
  aarch64|arm64)
    ARCH_TAG="aarch64"
    ;;
  *)
    echo "ERROR: Unsupported architecture: $HOST_ARCH. sagelite supports x86_64 and aarch64 (ARM64)." >&2
    exit 1
    ;;
esac

echo "============================================================"
echo "  Installing sagelite (Portable SageMath for Linux)"
echo "  Target Architecture: $ARCH_TAG"
echo "  Destination:         $INSTALL_DIR"
echo "  Repository:          $REPO"
echo "============================================================"

# Resolve download URL
if [ "$VERSION" = "latest" ]; then
  DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/sagemath-portable-${ARCH_TAG}.tar.zst"
else
  DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/sagemath-portable-${ARCH_TAG}.tar.zst"
fi

# Create install directory
mkdir -p "$INSTALL_DIR"

echo "==> [1/3] Downloading portable distribution archive..."
TEMP_ARCHIVE="$(mktemp --suffix=.tar.zst)"
trap 'rm -f "$TEMP_ARCHIVE"' EXIT

if command -v curl >/dev/null 2>&1; then
  curl -fL --progress-bar -o "$TEMP_ARCHIVE" "$DOWNLOAD_URL"
elif command -v wget >/dev/null 2>&1; then
  wget --show-progress -O "$TEMP_ARCHIVE" "$DOWNLOAD_URL"
else
  echo "ERROR: Neither curl nor wget was found. Please install curl or wget." >&2
  exit 1
fi

echo "==> [2/3] Extracting archive to $INSTALL_DIR..."
# Check for zstd support in tar
if tar --help 2>&1 | grep -q -- '--zstd'; then
  tar --zstd -xf "$TEMP_ARCHIVE" -C "$INSTALL_DIR" --strip-components=0
elif command -v zstd >/dev/null 2>&1; then
  zstd -d -c "$TEMP_ARCHIVE" | tar -xf - -C "$INSTALL_DIR" --strip-components=0
else
  echo "==> zstd utility not found. Bootstrapping extraction..."
  # If system tar lacks zstd, extract using standalone tar/zstd
  tar -xf "$TEMP_ARCHIVE" -C "$INSTALL_DIR" 2>/dev/null || {
    echo "ERROR: zstd is required to extract .tar.zst archives. Please install zstd (e.g. apt install zstd / dnf install zstd)." >&2
    exit 1
  }
fi

echo "==> [3/3] Creating executable symlink at $BIN_DIR/sage..."
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/sage" "$BIN_DIR/sage"

# Initializing one-time prefix setup
echo "==> Initializing portable prefix..."
"$INSTALL_DIR/sage" --version >/dev/null 2>&1 || true

echo ""
echo "============================================================"
echo "  Installation Complete!"
echo "============================================================"
echo "  Executable: $BIN_DIR/sage"
echo "  Run Sage:   sage"
echo "  Jupyter:    sage -n jupyter"
echo ""

# Check if ~/.local/bin is in PATH
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo "WARNING: $BIN_DIR is not currently in your \$PATH."
    echo "To run 'sage' directly from any terminal, add it to your PATH:"
    echo ""
    echo "    export PATH=\"$BIN_DIR:\$PATH\""
    echo ""
    echo "You can persist this by adding that line to your ~/.bashrc or ~/.zshrc."
    echo ""
    ;;
esac
