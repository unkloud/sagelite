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

# 0. Auto-bootstrap standalone micromamba if missing from PATH
if ! command -v micromamba >/dev/null 2>&1; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  CACHE_BIN="$PROJECT_ROOT/.cache/bin"
  
  if [ -x "$CACHE_BIN/micromamba" ]; then
    export PATH="$CACHE_BIN:$PATH"
  else
    echo "==> [0/4] Bootstrapping standalone micromamba for $MAMBA_ARCH..."
    mkdir -p "$CACHE_BIN"
    curl -fsSL "https://micro.mamba.pm/api/micromamba/${MAMBA_ARCH}/latest" | tar -xj -C "$CACHE_BIN" --strip-components=1 bin/micromamba
    export PATH="$CACHE_BIN:$PATH"
  fi
fi

echo "==> Using micromamba at: $(command -v micromamba)"
echo "==> Building recipe: $RECIPE_FILE"
echo "==> Target output: $OUTPUT_ARCHIVE"

# 1. Create the isolated Conda environment using micromamba
echo "==> [1/4] Creating isolated Conda environment using micromamba..."
micromamba create -y -n "$ENV_NAME" -f "$RECIPE_FILE"

# 2. Resolve environment prefix path
PREFIX="$(micromamba env list | awk -v env="$ENV_NAME" '$1 == env {print $NF}')"
if [ -z "$PREFIX" ] || [ ! -d "$PREFIX" ]; then
  for candidate in "${MAMBA_ROOT_PREFIX:-}/envs/$ENV_NAME" "$HOME/.local/share/mamba/envs/$ENV_NAME" "$HOME/micromamba/envs/$ENV_NAME"; do
    if [ -n "$candidate" ] && [ -d "$candidate" ]; then
      PREFIX="$candidate"
      break
    fi
  done
fi

if [ -z "$PREFIX" ] || [ ! -d "$PREFIX" ]; then
  echo "ERROR: Could not resolve prefix directory for environment '$ENV_NAME'." >&2
  exit 1
fi

echo "==> Environment staged at: $PREFIX"

# 3. Optimize payload size (strip redundant static files, docs, and debug symbols)
echo "==> [2/4] Optimizing payload (stripping non-essential files)..."

# 3.1. Remove libtool metadata (.la) and static libraries except compiler toolchain internals
find "$PREFIX" -type f -name "*.la" -delete
find "$PREFIX" -type f -name "*.a" \
  ! -path "*/lib/gcc/*" \
  ! -path "*/sysroot/*" \
  -delete

# 3.2. Remove unneeded documentation, manual pages, and test suites
rm -rf "$PREFIX/share/doc" \
       "$PREFIX/share/man" \
       "$PREFIX/lib/python"*/test \
       "$PREFIX/lib/python"*/site-packages/sage/tests

# 3.3. Strip unneeded debug symbols from native binaries and shared objects
find "$PREFIX/bin" "$PREFIX/lib" -type f -executable -exec strip --strip-unneeded {} + 2>/dev/null || true

# 3.4. Inject root wrapper script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/entrypoint.sh" "$PREFIX/sage"
chmod +x "$PREFIX/sage"

# 4. Package using conda-pack with multi-threaded Zstandard compression
echo "==> [3/4] Packaging with conda-pack (Zstandard level 19)..."
mkdir -p "$(dirname "$OUTPUT_ARCHIVE")"

# Locate conda-pack binary
if [ -x "$PREFIX/bin/conda-pack" ]; then
  PACK_BIN="$PREFIX/bin/conda-pack"
elif command -v conda-pack >/dev/null 2>&1; then
  PACK_BIN="$(command -v conda-pack)"
else
  echo "==> Installing conda-pack..."
  micromamba install -y -n "$ENV_NAME" conda-pack
  PACK_BIN="$PREFIX/bin/conda-pack"
fi

"$PACK_BIN" \
  -p "$PREFIX" \
  -o "$OUTPUT_ARCHIVE" \
  --compress-level 19 \
  --n-threads -1 \
  --ignore-missing-files \
  --format tar.zst \
  --force

# 5. Generate SHA256 checksum
echo "==> [4/4] Generating SHA256 checksum..."
(cd "$(dirname "$OUTPUT_ARCHIVE")" && sha256sum "$(basename "$OUTPUT_ARCHIVE")" > "$(basename "$OUTPUT_ARCHIVE").sha256")

echo "==> Build complete!"
echo "    Archive:  $OUTPUT_ARCHIVE ($(du -h "$OUTPUT_ARCHIVE" | cut -f1))"
echo "    Checksum: ${OUTPUT_ARCHIVE}.sha256"
