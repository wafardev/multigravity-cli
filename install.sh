#!/usr/bin/env bash
set -e

# multigravity installer
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing mgy to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME/.config/multigravity-profiles"

cp "$SCRIPT_DIR/bin/mgy" "$INSTALL_DIR/mgy"
chmod +x "$INSTALL_DIR/mgy"
ln -sf mgy "$INSTALL_DIR/multigravity"

echo "==> Successfully installed mgy (and multigravity alias) to $INSTALL_DIR"

# Check if INSTALL_DIR is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo "Notice: $INSTALL_DIR is not currently in your PATH."
    echo "Add the following line to your ~/.zshrc or ~/.bashrc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# Initialize default global config profiles
PROFILES_DIR="${MULTIGRAVITY_PROFILES_DIR:-$HOME/.config/multigravity-profiles}"
if [ ! -d "$PROFILES_DIR/perso" ] && [ -d "$HOME/.gemini/antigravity-cli" ]; then
    echo "==> Linking 'perso' profile to global ~/.gemini/antigravity-cli..."
    "$INSTALL_DIR/mgy" import perso >/dev/null 2>&1 || true
fi
if [ ! -d "$PROFILES_DIR/work" ]; then
    mkdir -p "$PROFILES_DIR/work/.gemini/antigravity-cli"
    [ -f "$HOME/.gitconfig" ] && ln -sf "$HOME/.gitconfig" "$PROFILES_DIR/work/.gitconfig"
    [ -d "$HOME/.ssh" ] && ln -sf "$HOME/.ssh" "$PROFILES_DIR/work/.ssh"
fi

echo ""
echo "Get started by running:"
echo "  mgy list"
echo "  mgy perso"
