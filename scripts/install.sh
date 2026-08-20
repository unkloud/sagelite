#!/usr/bin/env bash
set -euo pipefail

# Configuration defaults
REPO="${SAGELITE_REPO:-${GITHUB_REPOSITORY:-unkloud/sagelite}}"
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
      echo "Usage: curl -fsSL https://.../install.sh | bash -s -- [VERSION] [OPTIONS]"
      echo ""
      echo "Arguments:"
      echo "  VERSION             Optional release version tag (default: latest release, e.g. 10.9)"
      echo ""
      echo "Options:"
      echo "  -d, --dir=PATH      Installation target directory (default: ~/.local/share/sagelite)"
      echo "  -v, --version=TAG   Release version tag (default: latest)"
      echo "  --repo=OWNER/REPO   GitHub repository (default: unkloud/sagelite)"
      echo "  -h, --help          Show this help message"
      exit 0
      ;;
    [0-9]*|v[0-9]*)
      VERSION="$1"
      shift
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

# Resolve download URLs and determine release version
ARCHIVE_NAME="sagemath-portable-${ARCH_TAG}.tar.zst"
if [ "$VERSION" = "latest" ]; then
  # Dynamically fetch latest released tag name from GitHub API if reachable
  LATEST_TAG=""
  if command -v curl >/dev/null 2>&1; then
    LATEST_TAG="$(curl -fsSL -A "Mozilla/5.0 (X11; Linux x86_64)" "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep -m1 '"tag_name":' | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/' || true)"
  fi

  if [ -n "$LATEST_TAG" ]; then
    VERSION_DISPLAY="latest ($LATEST_TAG)"
    PRIMARY_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/${ARCHIVE_NAME}"
    FALLBACK_URL="https://github.com/${REPO}/releases/latest/download/${ARCHIVE_NAME}"
  else
    VERSION_DISPLAY="latest"
    PRIMARY_URL="https://github.com/${REPO}/releases/latest/download/${ARCHIVE_NAME}"
    FALLBACK_URL=""
  fi
else
  VERSION_DISPLAY="$VERSION"
  TAG_V="v${VERSION#v}"
  TAG_RAW="${VERSION#v}"
  PRIMARY_URL="https://github.com/${REPO}/releases/download/${TAG_V}/${ARCHIVE_NAME}"
  FALLBACK_URL="https://github.com/${REPO}/releases/download/${TAG_RAW}/${ARCHIVE_NAME}"
fi

echo "============================================================"
echo "  Installing sagelite (Portable SageMath for Linux)"
echo "  Version:             $VERSION_DISPLAY"
echo "  Target Architecture: $ARCH_TAG"
echo "  Destination:         $INSTALL_DIR"
echo "  Repository:          $REPO"
echo "============================================================"

# Create install directory
mkdir -p "$INSTALL_DIR"

echo "==> [1/3] Downloading portable distribution archive..."
TEMP_ARCHIVE="$(mktemp --suffix=.tar.zst)"
trap 'rm -f "$TEMP_ARCHIVE"' EXIT

download_file() {
  local url="$1"
  local dest="$2"

  # 1. Try aria2c (fastest: multi-connection parallel chunk downloading)
  if command -v aria2c >/dev/null 2>&1; then
    echo "==> Downloading via aria2c (accelerated multi-connection)..."
    if aria2c -x 16 -s 16 -k 1M --continue=true --auto-file-renaming=false \
      --header="User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0" \
      -d "$(dirname "$dest")" -o "$(basename "$dest")" "$url"; then
      return 0
    fi
  fi

  # 2. Try axel (multi-threaded download accelerator)
  if command -v axel >/dev/null 2>&1; then
    echo "==> Downloading via axel (multi-threaded)..."
    if axel -n 8 -a -o "$dest" "$url"; then
      return 0
    fi
  fi

  # 3. Optimized curl (browser User-Agent, 1MB buffer, automatic retries, resumption)
  if command -v curl >/dev/null 2>&1; then
    if curl -fL --progress-bar \
      -A "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0" \
      --retry 3 \
      --retry-delay 1 \
      --retry-connrefused \
      --buffer-size 1048576 \
      -C - \
      -o "$dest" "$url"; then
      return 0
    fi
  fi

  # 4. Optimized wget fallback
  if command -v wget >/dev/null 2>&1; then
    if wget --show-progress \
      --user-agent="Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0" \
      --tries=3 \
      -c \
      -O "$dest" "$url"; then
      return 0
    fi
  fi

  return 1
}

if ! download_file "$PRIMARY_URL" "$TEMP_ARCHIVE"; then
  if [ -n "$FALLBACK_URL" ] && download_file "$FALLBACK_URL" "$TEMP_ARCHIVE"; then
    echo "==> Downloaded from $FALLBACK_URL"
  else
    echo "ERROR: Failed to download release archive for version '$VERSION'." >&2
    echo "Please check available releases at: https://github.com/${REPO}/releases" >&2
    exit 1
  fi
fi

echo "==> [2/3] Extracting archive to $INSTALL_DIR..."
# Check for zstd support in tar
if tar --help 2>&1 | grep -q -- '--zstd'; then
  tar --zstd -xf "$TEMP_ARCHIVE" -C "$INSTALL_DIR" --strip-components=0
elif command -v zstd >/dev/null 2>&1; then
  zstd -d -c "$TEMP_ARCHIVE" | tar -xf - -C "$INSTALL_DIR" --strip-components=0
else
  echo "==> zstd utility not found. Bootstrapping extraction..."
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
