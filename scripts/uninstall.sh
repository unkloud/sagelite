#!/usr/bin/env bash
set -euo pipefail

DEFAULT_INSTALL_DIR="$HOME/.local/share/sagelite"
BIN_DIR="$HOME/.local/bin"
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
ASSUME_YES=false

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
    --yes|-y)
      ASSUME_YES=true
      shift
      ;;
    --help|-h)
      echo "sagelite uninstaller"
      echo ""
      echo "Usage: ./scripts/uninstall.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -d, --dir=PATH      Installation directory to remove (default: ~/.local/share/sagelite)"
      echo "  -y, --yes           Skip confirmation prompt"
      echo "  -h, --help          Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

echo "============================================================"
echo "  sagelite Uninstaller"
echo "============================================================"
echo "Target installation directory: $INSTALL_DIR"
echo "Target binary symlink:         $BIN_DIR/sage"
echo ""

if [ "$ASSUME_YES" = false ]; then
  read -r -p "Are you sure you want to remove sagelite? [y/N] " response
  case "$response" in
    [yY][eE][sS]|[yY]) ;;
    *)
      echo "Uninstallation aborted."
      exit 0
      ;;
  esac
fi

# Remove installation directory
if [ -d "$INSTALL_DIR" ]; then
  echo "==> Removing directory: $INSTALL_DIR..."
  rm -rf "$INSTALL_DIR"
  echo "    [DONE] Removed $INSTALL_DIR"
else
  echo "    [SKIP] Directory $INSTALL_DIR does not exist."
fi

# Remove symlink
if [ -L "$BIN_DIR/sage" ] || [ -f "$BIN_DIR/sage" ]; then
  echo "==> Removing symlink: $BIN_DIR/sage..."
  rm -f "$BIN_DIR/sage"
  echo "    [DONE] Removed $BIN_DIR/sage"
else
  echo "    [SKIP] Symlink $BIN_DIR/sage does not exist."
fi

# Clean up desktop shortcuts and icons if present
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor"
REMOVED_DESKTOP=false

for dfile in "$DESKTOP_DIR/sagelite"*.desktop; do
  if [ -f "$dfile" ]; then
    echo "==> Removing desktop launcher: $dfile..."
    rm -f "$dfile"
    REMOVED_DESKTOP=true
  fi
done

for ifile in "$ICON_DIR"/*/apps/sagelite.*; do
  if [ -f "$ifile" ]; then
    echo "==> Removing icon: $ifile..."
    rm -f "$ifile"
  fi
done

if [ "$REMOVED_DESKTOP" = true ] && command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi

echo ""
echo "============================================================"
echo "  sagelite has been successfully uninstalled."
echo "============================================================"
