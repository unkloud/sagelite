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

# Multi-hop dynamic prefix relocation handling
if [ ! -f "$DIR/.last_prefix" ]; then
  # First initialization: execute conda-unpack against null-padded placeholders
  if [ -f "$DIR/bin/conda-unpack" ]; then
    "$DIR/bin/python" "$DIR/bin/conda-unpack" >/dev/null 2>&1 || true
  fi
  echo "$DIR" > "$DIR/.last_prefix"
  touch "$DIR/.unpacked"
else
  # Secondary movement / USB mount path changes: re-patch text shebangs and configuration files
  PREV_DIR="$(cat "$DIR/.last_prefix" 2>/dev/null || true)"
  if [ -n "$PREV_DIR" ] && [ "$PREV_DIR" != "$DIR" ]; then
    if command -v sed >/dev/null 2>&1; then
      SEARCH_DIRS=()
      for d in "$DIR/bin" "$DIR/etc" "$DIR/lib/pkgconfig" "$DIR/share/pkgconfig" "$DIR/lib/python"*/site-packages/sage; do
        [ -d "$d" ] && SEARCH_DIRS+=("$d")
      done
      if [ ${#SEARCH_DIRS[@]} -gt 0 ]; then
        find "${SEARCH_DIRS[@]}" -type f -exec grep -Il "$PREV_DIR" {} + 2>/dev/null | while IFS= read -r f; do
          sed -i "s|$PREV_DIR|$DIR|g" "$f" 2>/dev/null || true
        done
      fi
    fi
    echo "$DIR" > "$DIR/.last_prefix"
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
export ECL_CONFIG="$DIR/bin/ecl-config"
export MAXIMA="$DIR/bin/maxima"
export SINGULAR_BIN="$DIR/bin/Singular"

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
