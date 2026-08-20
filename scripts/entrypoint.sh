#!/usr/bin/env bash
# Distribution root wrapper: sage
set -euo pipefail

# Resolve directory location independent of invocation path or symlinks
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

# Fixed-target prefix initialization (runs conda-unpack once at target destination)
SENTINEL="$DIR/.unpacked"
if [ ! -f "$SENTINEL" ]; then
  if [ -f "$DIR/bin/conda-unpack" ]; then
    "$DIR/bin/python" "$DIR/bin/conda-unpack" >/dev/null 2>&1 || true
  fi
  echo "$DIR" > "$SENTINEL"
else
  # Safety check: detect if directory was moved after initial unpack
  RECORDED_DIR="$(head -n 1 "$SENTINEL" 2>/dev/null || true)"
  if [ -n "$RECORDED_DIR" ] && [ "$RECORDED_DIR" != "$DIR" ]; then
    echo "ERROR: sagelite was initialized at '$RECORDED_DIR' and moved to '$DIR'." >&2
    echo "Binary offsets were patched during the initial run. To run from '$DIR'," >&2
    echo "please extract the original .tar.zst archive directly into the target directory:" >&2
    echo "    tar --zstd -xf sagemath-portable-<arch>.tar.zst -C $DIR" >&2
    exit 1
  fi
fi

# Sanitize environment to prevent host Python and library bleed
unset PYTHONPATH
unset PYTHONSTARTUP
export SAGE_ROOT="$DIR"
export SAGE_LOCAL="$DIR"
export CONDA_PREFIX="$DIR"
export PYTHONNOUSERSITE=1
export PYTHONHOME="$DIR"
export PATH="$DIR/bin:$PATH"
export LD_LIBRARY_PATH="$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="$DIR/lib/pkgconfig:$DIR/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# Source compiler toolchain and runtime activation scripts (sets CC, CXX, --sysroot, etc.)
if [ -d "$DIR/etc/conda/activate.d" ]; then
  for act_script in "$DIR/etc/conda/activate.d"/*.sh; do
    if [ -f "$act_script" ]; then
      source "$act_script" >/dev/null 2>&1 || true
    fi
  done
fi

# Fallback compiler toolchain exports if not set by activation scripts
if [ -z "${CC:-}" ]; then
  HOST_M="$(uname -m)"
  case "$HOST_M" in
    x86_64)  ARCH_PREFIX="x86_64-conda-linux-gnu-" ;;
    aarch64) ARCH_PREFIX="aarch64-conda-linux-gnu-" ;;
    *)       ARCH_PREFIX="" ;;
  esac
  if [ -n "$ARCH_PREFIX" ] && [ -x "$DIR/bin/${ARCH_PREFIX}gcc" ]; then
    export CC="$DIR/bin/${ARCH_PREFIX}gcc"
    export CXX="$DIR/bin/${ARCH_PREFIX}g++"
    export FC="$DIR/bin/${ARCH_PREFIX}gfortran"
  elif [ -x "$DIR/bin/gcc" ]; then
    export CC="$DIR/bin/gcc"
    export CXX="$DIR/bin/g++"
    export FC="$DIR/bin/gfortran"
  fi
fi

# Convenience sub-command forwarding
if [ $# -gt 0 ]; then
  case "$1" in
    -pip|--pip|pip)
      shift
      exec "$DIR/bin/python" -m pip "$@"
      ;;
    -python|--python|python)
      shift
      exec "$DIR/bin/python" "$@"
      ;;
    -pytest|--pytest|pytest)
      shift
      exec "$DIR/bin/python" -m pytest "$@"
      ;;
    -gap|--gap|gap)
      shift
      exec "$DIR/bin/gap" "$@"
      ;;
    -singular|--singular|singular)
      shift
      exec "$DIR/bin/Singular" "$@"
      ;;
    -gp|--gp|gp)
      shift
      exec "$DIR/bin/gp" "$@"
      ;;
  esac
fi

# Route execution directly to internal Sage runtime using bundled Python
if [ -f "$DIR/bin/sage" ]; then
  exec "$DIR/bin/python" "$DIR/bin/sage" "$@"
else
  exec "$DIR/bin/python" -m sage.cli.__main__ "$@"
fi
