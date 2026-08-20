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
      shift
      exec "$DIR/bin/pip" "$@"
      ;;
    -python|--python|python)
      shift
      exec "$DIR/bin/python" "$@"
      ;;
    -pytest|--pytest|pytest)
      shift
      exec "$DIR/bin/pytest" "$@"
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

# Route execution directly to internal Sage runtime
exec "$DIR/bin/sage" "$@"
