#!/usr/bin/env bash
set -e

# multigravity installer
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing multigravity to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME/.config/multigravity-profiles"

cp "$SCRIPT_DIR/bin/multigravity" "$INSTALL_DIR/multigravity"
chmod +x "$INSTALL_DIR/multigravity"

echo "==> Successfully installed multigravity to $INSTALL_DIR/multigravity"

# Check if INSTALL_DIR is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo "Notice: $INSTALL_DIR is not currently in your PATH."
    echo "Add the following line to your ~/.zshrc or ~/.bashrc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "Get started by running:"
echo "  multigravity help"
